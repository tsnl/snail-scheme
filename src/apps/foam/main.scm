;; Fit, render and inspect a Radiant Foam on WebGPU or the reference CPU backend.
;; ./snail-scheme run --target node src/apps/foam/main.scm
(import
 (snail core base)
 (snail core io)
 (snail core table)
 (snail shell wire)
 (snail shell gpu)
 (only (snail shell json) JsonNumber JsonInteger)
 (only (snail shell json read) string->json)
 (snail shell graphics radiant-foam)
 (snail shell graphics radiant-foam-gpu)
 (only (apps train dataset) settings-of setting)
 (apps foam views))

;; ---- Fitting and rendering ----

(define (fit (initial Foam) (samples (Array Sample)) (steps I64) (batch I64) (rate F64)) (→ Foam)
  (do ((i 0 (+ i 1))
       (foam initial (fit-step foam (map (lambda (j) (array-ref samples j))
                                         (sample-batch (array-length samples) batch i)) rate)))
      ((= i steps) foam)))

(define (draw (foam Foam) (view View)) (→ (Array Vec3d))
  (array-map (lambda (s) (render-ray foam (● s ray))) (● view samples)))

(define (mse (drawn (Array Vec3d)) (view View)) (→ F64)
  (let loop ((i 0) (total 0.0))
    (if (= i (array-length drawn)) (/ total (* 3.0 (i64->f64 i)))
        (let ((error (v- (array-ref drawn i) (● (array-ref (● view samples) i) rgb))))
          (loop (+ i 1) (+ total (dot error error)))))))

;; ---- The threshold surface ----

;; Several cells compute each corner. Weld roundoff in normalized
;; coordinates, then write the shared corner at full world precision.
(define (vertex-key (p Vec3d)) (→ String)
  (let ((key (lambda (x) (show (f64->i64 (round (* 1e9 x)))))))
    (string-join (map key (list (● p x) (● p y) (● p z))) " ")))

(define (vertex-line (model Model) (p Vec3d)) (→ String)
  (let ((w (v+ (● model center) (v* p (● model radius)))))
    (string-append "v " (string-join (map f64->string (list (● w x) (● w y) (● w z))) " "))))

(define (triangles (indices (List I64))) (→ (List String))
  (match indices
    ((Cons a (Cons b rest))
     (let loop ((b b) (rest rest) (lines (Nil)))
       (match rest
         ((Nil) (reverse lines))
         ((Cons c tail)
          (loop c tail (if (or (= a b) (= a c) (= b c)) lines
                           (Cons (string-append "f " (show a) " " (show b) " " (show c))
                                 lines)))))))
    (_ (Nil))))

(define (surface-obj (model Model) (faces (List (List Vec3d))) (threshold F64)) (→ String)
  (let* ((points (table-values (fold-left (lambda (t p) (table-set t (vertex-key p) p))
                                          (empty-table) (concatenate faces))))
         (ids (fold-left
               (lambda (t pair) (table-set t (vertex-key (● pair second)) (+ (● pair first) 1)))
               (empty-table) (zip (iota (length points)) points)))
         (index (lambda (p) (match (table-ref ids (vertex-key p))
                              ((Some i) i) ((None) (panic "missing face vertex")))))
         (facets (concatenate (map (lambda (face) (triangles (map index face))) faces))))
    (string-append "# Voronoi interfaces at density " (f64->string threshold) " per model unit\n"
                   (string-join (append (map (lambda (p) (vertex-line model p)) points) facets)
                                "\n")
                   "\n")))

;; ---- The run ----

(define (option (query String) (key String) (fallback String)) (→ String)
  (match (setting query key) ((Some value) value) ((None) fallback)))

(define (count-option (query String) (key String) (fallback String)) (→ I64)
  (match (string->i64 (option query key fallback))
    ((Some n) (if (>= n 0) n (panic (string-append key " must be nonnegative"))))
    ((None) (panic (string-append key " needs a whole number")))))

(define (number-option (query String) (key String) (fallback String)) (→ F64)
  (match (string->json (option query key fallback))
    ((Some (JsonInteger n)) (i64->f64 n))
    ((Some (JsonNumber n)) n)
    (_ (panic (string-append key " needs a number")))))

(define (positive-option (query String) (key String) (fallback String)) (→ I64)
  (let ((n (count-option query key fallback)))
    (if (> n 0) n (panic (string-append key " must be positive")))))

(record Fitted
  ((sites Foam)
   (before (Array Vec3d))
   (after (Array Vec3d))))

(define (elapsed-ms (clock Clock) (start I64)) (→ String)
  (f64->string (/ (i64->f64 (- ((● clock monotonic-nanoseconds)) start)) 1000000.0)))

(define (cpu-fit (out OutputPort) (clock Clock) (exp Experiment) (steps I64) (batch I64) (rate F64))
  (→ Fitted)
  (let* ((initial (make-foam (● exp initial sites))) (before (draw initial (● exp held)))
         (start ((● clock monotonic-nanoseconds)))
         (trained (fit initial (● exp training) steps batch rate)))
    (write-line out (string-append "CPU fitting " (elapsed-ms clock start) " ms"))
    (let* ((at ((● clock monotonic-nanoseconds))) (after (draw trained (● exp held))))
      (write-line out (string-append "CPU frame " (elapsed-ms clock at) " ms"))
      (new Fitted (sites trained) (before before) (after after)))))

(define (gpu-draw (gpu Gpu) (view FoamView)) (→ (Array Vec3d))
  (let* ((encoder ((● gpu create-command-encoder))) (pass ((● gpu begin-compute-pass) encoder)))
    (dispatch-foam-view gpu pass view)
    ((● gpu end-compute-pass) pass)
    ((● gpu submit) (list ((● gpu finish) encoder)))
    (read-foam-view gpu view)))

;; Each timestamp pair encloses just the compute pass for a resident view.
(define (frame-ms (gpu Gpu) (view FoamView) (queries GpuQuerySet)) (→ F64)
  (let* ((encoder ((● gpu create-command-encoder)))
         (pass ((● gpu begin-timed-compute-pass) encoder
                (new TimestampWrites (query-set queries) (beginning 0) (end 1)))))
    (dispatch-foam-view gpu pass view)
    ((● gpu end-compute-pass) pass)
    (* 1000.0 (elapsed-seconds (submit-timed gpu encoder queries 2) 0 1))))

(define (profile-view (out OutputPort) (gpu Gpu) (view FoamView) (frames I64)) (→ Unit)
  (let* ((queries
          ((● gpu create-query-set) (new QuerySetDescriptor (label "foam/frame") (count 2))))
         (times (list-sort < (map (lambda (_) (frame-ms gpu view queries)) (iota frames)))))
    (write-line out (string-append "GPU frame " (f64->string (list-ref times (quotient frames 2)))
                                   " ms (median of " (show frames) " warmed compute passes)"))
    ((● gpu destroy) (QuerySetObject queries))))

(define (gpu-fit (out OutputPort) (clock Clock) (gpu Gpu) (exp Experiment)
                 (steps I64) (batch I64) (rate F64) (frames I64))
  (→ Fitted)
  (let* ((initial (make-foam (● exp initial sites))) (foam (make-device-foam gpu initial))
         (held (● exp held))
         (view (make-foam-view gpu foam (● held camera) (● held width) (● held height)))
         (before (gpu-draw gpu view)))
    (when (> steps 0)
      (let ((trainer (make-foam-trainer gpu foam (● exp training) batch)))
        ((● gpu work-done))
        (let ((start ((● clock monotonic-nanoseconds))))
          (train-foam! gpu trainer 0 steps rate)
          ((● gpu work-done))
          (write-line out (string-append "GPU fitting " (elapsed-ms clock start) " ms")))
        (release-foam-trainer gpu trainer)))
    ;; Rendering a checkpoint alone preserves its original F64 sites for
    ;; re-export, including densities immediately beside the threshold.
    (let ((after (if (= steps 0) before (gpu-draw gpu view)))
          (trained (if (= steps 0) initial (read-foam gpu foam))))
      (when (> frames 0) (profile-view out gpu view frames))
      (release-foam-view gpu view)
      (release-device-foam gpu foam)
      (new Fitted (sites trained) (before before) (after after)))))

(define (write-fit (fs Fs) (out OutputPort) (directory String) (experiment Experiment)
                   (fit Fitted) (steps I64) (level F64))
  (→ Unit)
  (let* ((path (lambda (name) (string-append directory "/" name)))
         (view (● experiment held)) (model (● experiment initial))
         (trained (● fit sites)) (before (● fit before)) (after (● fit after))
         (faces (density-faces trained level)))
    (write-bytes fs (path "model.foam") (serialize (new Model
                                                     (center (● model center))
                                                     (radius (● model radius))
                                                     (sites (array->list trained)))))
    (write-file fs (path "surface.obj") (surface-obj model faces level))
    (write-bytes fs
                 (path "target.png")
                 (rgb-png (● view width)
                          (● view height)
                          (array-map (lambda (s) (● s rgb)) (● view samples))))
    (write-bytes fs (path "before.png") (rgb-png (● view width) (● view height) before))
    (write-bytes fs (path "render.png") (rgb-png (● view width) (● view height) after))
    (write-line out (string-append (show (array-length trained)) " sites, " (show steps)
                                   " steps, held-out " (● view name) " " (show (● view width)) "x"
                                   (show (● view height))
                                   ", RGB MSE "
                                   (f64->string (mse before view))
                                   " -> " (f64->string (mse after view))))
    (write-line out
                (string-append (show (length faces)) " density interfaces at " (f64->string level)
                               " written to " (path "surface.obj")))))

(define (main (host Host) (arguments Arguments) (fs Fs) (out OutputPort) (clock Clock)) (→ Unit)
  (let* ((query (string-append "?" (string-join (list-tail (command-line arguments) 1) "&")))
         (saved (match (setting query "load")
                  ((Some path) (Some (ann (deserialize (read-bytes fs path)) Model)))
                  ((None) (None))))
         (steps (count-option query "steps" (match saved ((Some _) "0") ((None) "500"))))
         (batch (positive-option query "batch" "96")) (rate (number-option query "rate" "1.0"))
         (index (count-option query "view" "0")) (width (positive-option query "width" "96"))
         (sites (positive-option query "sites" "48")) (directory (option query "out" "build/foam"))
         (level (number-option query "threshold" "1.0")) (frames (count-option query "frames" "0"))
         (backend (option query "backend" "gpu"))
         (gpu (host-gpu host))
         (scene (setting query "scene")))
    (unless (or (string=? backend "gpu") (string=? backend "cpu"))
      (panic "backend must be gpu or cpu"))
    (when (or (string=? backend "gpu") (match scene ((Some _) #t) ((None) #f)))
      (let ((info ((● gpu request-device))))
        (when (and (> frames 0)
                   (string=? backend "gpu")
                   (not (member? "timestamp-query" (● info features))))
          (panic "frames needs GPU timestamp-query support"))))
    (match (make-directories fs directory)
      ((Err _) (panic (string-append "cannot create " directory))) ((Ok _) (unit)))
    (let* ((experiment (match scene
                         ((None) (demo-experiment saved (> steps 0) index width))
                         ((Some _) (photo-experiment gpu (lambda (p) (read-bytes fs p))
                                                     (settings-of query)
                                                     saved
                                                     (> steps 0)
                                                     index
                                                     sites
                                                     width))))
           (fitted
            (if (string=? backend "gpu") (gpu-fit out clock gpu experiment steps batch rate frames)
                (cpu-fit out clock experiment steps batch rate))))
      (write-fit fs out directory experiment fitted steps level))))
