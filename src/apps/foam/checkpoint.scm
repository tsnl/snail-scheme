;; Render the released RadFoam checkpoint at the dataset's held-out cameras.
(import
 (snail core base)
 (snail core io)
 (only (snail shell math) log)
 (snail shell gpu)
 (snail shell graphics colmap)
 (snail shell graphics radiant-foam)
 (snail shell graphics radiant-foam-gpu)
 (only (snail shell graphics splat-fit) texel-pitch)
 (apps train dataset)
 (only (apps foam views) pose-camera photo-bytes rgb-png))

(define (option (query String) (key String) (fallback String)) (→ String)
  (match (setting query key) ((Some value) value) ((None) fallback)))

(define (count-option (query String) (key String) (fallback I64)) (→ I64)
  (match (string->i64 (option query key (show fallback)))
    ((Some n) (if (>= n 0) n (panic (string-append key " must be nonnegative"))))
    ((None) (panic (string-append key " needs an integer")))))

(define (render (gpu Gpu) (foam FoamCheckpoint)) (→ (Array Vec3d))
  (let* ((encoder ((● gpu create-command-encoder))) (pass ((● gpu begin-compute-pass) encoder)))
    (dispatch-foam-checkpoint gpu pass foam)
    ((● gpu end-compute-pass) pass)
    ((● gpu submit) (list ((● gpu finish) encoder)))
    (read-foam-checkpoint gpu foam)))

(define (timed-frames (gpu Gpu) (foam FoamCheckpoint) (q GpuQuerySet) (frames I64)) (→ (List F64))
  (let* ((encoder ((● gpu create-command-encoder))) (warm ((● gpu begin-compute-pass) encoder)))
    (dispatch-foam-checkpoint gpu warm foam)
    ((● gpu end-compute-pass) warm)
    (do ((i 0 (+ i 1))) ((= i frames) (unit))
      (let* ((at (i64->i32 (* 2 i)))
             (pass ((● gpu begin-timed-compute-pass) encoder
                    (new TimestampWrites (query-set q) (beginning at) (end (+ at 1))))))
        (dispatch-foam-checkpoint gpu pass foam)
        ((● gpu end-compute-pass) pass)))
    (let ((times (submit-timed gpu encoder q (i64->i32 (* 2 frames)))))
      (map (lambda (i) (let ((at (i64->i32 (* 2 i))))
                         (* 1000.0 (elapsed-seconds times at (+ at 1))))) (iota frames)))))

(define (timing (gpu Gpu) (foam FoamCheckpoint) (queries (Option GpuQuerySet)) (frames I64))
  (→ String)
  (match queries
    ((None) "")
    ((Some q)
     (let ((times (list-sort < (timed-frames gpu foam q frames))))
       (string-append ", " (f64->string (list-ref times (quotient frames 2))) " ms")))))

(record ImagePsnr
  ((rgb F64)
   (channels F64)))

(define (psnr (mse F64)) (→ F64)
  (* -10.0 (/ (log mse) (log 10.0))))

;; The splat benchmark pools RGB error before taking the log. Upstream
;; RadFoam takes the log for each channel first. Both average over views.
(define (photo-psnr (drawn (Array Vec3d)) (photo Bytes) (w I64) (pitch I64)) (→ ImagePsnr)
  (let* ((n (array-length drawn))
         (channel (lambda (k) (/ (i32->f64 (u8->i32 (array-ref photo k))) 255.0)))
         (square (lambda (v) (* v v))))
    (let loop ((i 0) (r 0.0) (g 0.0) (b 0.0))
      (if (= i n)
          (let ((pixels (i64->f64 n)))
            (new ImagePsnr (rgb (psnr (/ (+ r (+ g b)) (* 3.0 pixels))))
                 (channels
                  (/ (+ (psnr (/ r pixels)) (+ (psnr (/ g pixels)) (psnr (/ b pixels)))) 3.0))))
          (let ((k (+ (* (quotient i w) pitch) (* 4 (remainder i w)))) (v (array-ref drawn i)))
            (loop (+ i 1) (+ r (square (- (● v x) (channel k))))
                  (+ g (square (- (● v y) (channel (+ k 1)))))
                  (+ b (square (- (● v z) (channel (+ k 2)))))))))))

(define (score-text (score ImagePsnr)) (→ String)
  (string-append (f64->string (● score rgb)) " dB RGB, "
                 (f64->string (● score channels)) " dB mean-channel"))

(define (mean-scores (scores (List ImagePsnr))) (→ ImagePsnr)
  (let ((n (i64->f64 (length scores))))
    (new ImagePsnr (rgb (/ (fold-left (lambda (s p) (+ s (● p rgb))) 0.0 scores) n))
         (channels (/ (fold-left (lambda (s p) (+ s (● p channels))) 0.0 scores) n)))))

(define (photograph (gpu Gpu) (fs Fs) (settings Settings) (cam ColmapCamera) (pose ColmapImage))
  (→ Bytes)
  (let ((image (dataset-photograph gpu (lambda (p) (read-bytes fs p)) settings pose)))
    (unless (and (= (● pose camera) (● cam id))
                 (= (i32->i64 (● image width)) (● cam width))
                 (= (i32->i64 (● image height)) (● cam height)))
      (panic "RadFoam evaluation needs one pinhole camera and photographs at its resolution"))
    (photo-bytes gpu image (i64->i32 (* 4 (texel-pitch (● cam width)))))))

(define (score (gpu Gpu) (fs Fs) (out OutputPort) (foam FoamCheckpoint) (settings Settings)
               (cam ColmapCamera) (pose ColmapImage) (directory String)
               (queries (Option GpuQuerySet)) (frames I64))
  (→ ImagePsnr)
  (set-checkpoint-camera! gpu foam (pose-camera cam pose (vec3d 0.0 0.0 0.0) 1.0))
  (let* ((w (● cam width)) (h (● cam height)) (image (render gpu foam))
         (psnr (photo-psnr image
                           (photograph gpu fs settings cam pose)
                           w
                           (* 4 (texel-pitch w)))))
    (write-bytes fs
                 (string-append directory "/camera-" (show (● pose id)) ".png")
                 (rgb-png w h image))
    (write-line out (string-append (● pose name) " " (score-text psnr)
                                   (timing gpu foam queries frames)))
    psnr))

(define (main (host Host) (arguments Arguments) (fs Fs) (out OutputPort)) (→ Unit)
  (let* ((query (string-append "?" (string-join (list-tail (command-line arguments) 1) "&")))
         (path (match (setting query "checkpoint")
                 ((Some p) p)
                 ((None) (panic "supply checkpoint=DIR"))))
         (gpu (host-gpu host)) (features (● ((● gpu request-device)) features))
         (read (lambda (p) (read-bytes fs p))) (settings (settings-of query))
         (scene (dataset-scene gpu read settings)) (cam (● scene camera)) (held (● scene held))
         (n (min (length held) (count-option query "views" (length held))))
         (frames (count-option query "frames" 0))
         (directory (option query "out" "build/foam-checkpoint")))
    (when (= n 0) (panic "evaluation needs a held-out camera"))
    (when (> frames 2048) (panic "a WebGPU query set holds up to 2048 timestamp pairs"))
    (when (and (> frames 0) (not (member? "timestamp-query" features)))
      (panic "frames needs GPU timestamp-query support"))
    (match (make-directories fs directory) ((Err e) (panic (show e))) ((Ok _) (unit)))
    (let* ((foam (open-foam-checkpoint gpu (lambda (name) (read (string-append path "/" name)))
                                       (● cam width) (● cam height)))
           (q (if (= frames 0) (None)
                  (Some ((● gpu create-query-set)
                         (new QuerySetDescriptor
                           (label "radfoam/frame")
                           (count (i64->i32 (* 2 frames)))))))))
      (write-line out (string-append (show (● foam count)) " sites, " (show n) " held-out cameras"))
      (let ((scores
             (map (lambda (pose) (score gpu fs out foam settings cam pose directory q frames))
                  (take held n))))
        (write-line out (string-append "Mean held-out PSNR " (score-text (mean-scores scores)))))
      (match q ((Some handle) ((● gpu destroy) (QuerySetObject handle))) ((None) (unit)))
      (release-foam-checkpoint gpu foam))))
