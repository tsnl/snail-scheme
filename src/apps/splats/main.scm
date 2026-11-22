;; Splats: gaussian splatting through (snail shell graphics splat), flown
;; through with the mouse and keys. The page opens on three turning rings
;; ((apps splats rings)). A scene trained by 3D Gaussian Splatting, the
;; .ply file its reference implementation writes, takes their place:
;; dropped on the page, picked with O, or named by the page's query,
;; `?cloud=ADDRESS`.
;;
;; Such a scene stands in its reconstruction's frame, which has no up of
;; its own, so the cameras that photographed it say which way is up:
;; COLMAP's `images.bin`, among the files chosen or at `&poses=ADDRESS`.
;; The cloud is turned upright by its row of the transforms table, and
;; the view starts at the first camera. Without poses, up is COLMAP's own
;; -y, and the view starts back from the middle of the cloud. Files that
;; cannot be shown leave the view as it was, and the page says why.
(import
 (snail core base)
 (snail core io)
 (only (snail shell task) tasks)
 (only (snail shell app) next-event FrameEvent InputEvent FilesEvent KeyDown)
 (only (snail shell page) Events report-ready)
 (only (snail shell fetch) Fetch fetch-all-bytes page-address)
 (only (snail shell dom) Dom document-root set-text)
 (only (snail shell dom page) with-page-dom)
 (snail shell files)
 (snail shell files page)
 (snail shell fetch page)
 (snail shell gpu)
 (snail shell graphics pod)
 (only (snail shell graphics gltf) uri-path reading unreadable attempt-reading)
 (snail shell graphics colmap)
 (snail shell graphics ply)
 (snail shell graphics splat)
 (snail shell graphics fly)
 (apps splats rings))

;; ---- The view ----

;; What is drawn: the one splats on the device, and the seconds the rings
;; have turned, which pose them each frame, or none for a file's cloud,
;; which is posed once.
(record Shown
  ((splats Splats)
   (turned (Option F64))))

(define (view-loop (gpu Gpu) (dom Dom) (picker FilePicker) (events Events) (fetch Fetch) (out OutputPort) (shown Shown) (fly Fly) (timing (Pair I32 I32)) (format TextureFormat))
  (→ Unit)
  (! mut tasks)
  (match (next-event events)
    ((FrameEvent elapsed)
     (let ((shown (turning gpu shown elapsed)) (fly (flown fly elapsed)))
       (frame gpu (● shown splats) fly)
       (work-done gpu)
       (report-ready events)
       (view-loop gpu dom picker events fetch out shown fly (timed out timing elapsed) format)))
    ((InputEvent (KeyDown 111 _)) (open-picker picker (SomeFiles)) (view-loop gpu dom picker events fetch out shown fly timing format))
    ((InputEvent input) (view-loop gpu dom picker events fetch out shown (steered fly input) timing format))
    ((FilesEvent _) (opened gpu dom picker events fetch out shown fly timing format (chosen-files picker)))
    (_ (view-loop gpu dom picker events fetch out shown fly timing format))))

;; The rings posed where `elapsed` more milliseconds turn them.
(define (turning (gpu Gpu) (shown Shown) (elapsed I32)) (→ Shown) (! mut)
  (match (● shown turned)
    ((Some seconds)
     (let ((now (+ seconds (/ (i32->f64 elapsed) 1000.0))))
       (write-transforms gpu (● shown splats) (ring-poses now))
       (Shown-turned-set shown (Some now))))
    ((None) shown)))

;; The splats sorted from where the fly is, and drawn into the canvas.
(define (frame (gpu Gpu) (splats Splats) (fly Fly)) (→ Unit) (! mut)
  (let* ((canvas (current-texture gpu)) (encoder (create-command-encoder gpu)))
    (sort-splats gpu encoder
                 splats
                 (splat-camera (fly-eye fly)
                               (fly-target fly)
                               (new Vec3f (x 0.0) (y 1.0) (z 0.0))
                               fly-fov
                               (● canvas width)
                               (● canvas height)))
    (let ((pass (begin-render-pass gpu encoder
                                   (new RenderPassDescriptor
                                     (colors (list (Some (new ColorAttachment
                                                           (view (view-of gpu (● canvas texture) 1))
                                                           (load (Clear (new Color
                                                                          (red 0.02)
                                                                          (green 0.02)
                                                                          (blue 0.03)
                                                                          (alpha 1.0))))
                                                           (store #t)))))
                                     (depth (None))))))
      (draw-splats gpu pass splats)
      (end-pass gpu pass))
    (submit gpu (list (finish gpu encoder)))))

;; Frames and milliseconds since the last report, which comes every two
;; seconds.
(define (timed (out OutputPort) (timing (Pair I32 I32)) (elapsed I32)) (→ (Pair I32 I32)) (! mut)
  (let ((frames (+ 1 (● timing first))) (total (+ elapsed (● timing second))))
    (if (< total 2000)
        (new Pair (first frames) (second total))
        (begin
          (write-line out (string-append "frames: " (show frames) " in " (show total) " ms"))
          (new Pair (first 0) (second 0))))))

;; A cloud on the device, with `rows` rows of transforms to pose it by.
(define (standing (gpu Gpu) (cloud Cloud) (rows I64) (format TextureFormat)) (→ Splats) (! mut)
  (let ((splats (make-splats gpu "cloud" format (● cloud count) rows)))
    (write-cloud gpu splats 0 cloud)
    splats))

;; ---- The files chosen ----

;; A cloud, and the poses of the cameras that photographed it when the
;; files hold them.
(record Scene
  ((cloud Cloud)
   (poses (List ColmapImage))))

;; The view of the files chosen, upright, the fly at the scene's start;
;; or the view as it was, and why, when they cannot be shown. Everything
;; is read before the device is touched, so files refused leave nothing
;; on it, and the splats shown are let go only once theirs can follow.
(define (opened (gpu Gpu) (dom Dom) (picker FilePicker) (events Events) (fetch Fetch) (out OutputPort) (shown Shown)
                (fly Fly)
                (timing (Pair I32 I32))
                (format TextureFormat)
                (files (List Chosen)))
  (→ Unit)
  (! mut tasks)
  (set-text dom (document-root dom) "Loading…")
  (match (attempt-reading (lambda () (chosen fetch files)))
    ((Ok scene)
     (release-splats gpu (● shown splats))
     (say dom out (string-append (show (● (● scene cloud) count)) " gaussians"))
     (let ((turn (upright (poses-up (● scene poses))))
           (splats (standing gpu (● scene cloud) 1 format)))
       (write-transforms gpu splats (list (pose turn 0.0 0.0 0.0)))
       (view-loop gpu dom picker events fetch out (new Shown (splats splats) (turned (None))) (start-of scene turn) timing format)))
    ((Err why) (say dom out why) (view-loop gpu dom picker events fetch out shown fly timing format))))

;; What the page says beside the view, and the console with it.
(define (say (dom Dom) (out OutputPort) (message String)) (→ Unit) (! mut)
  (set-text dom (document-root dom) message)
  (write-line out message))

;; The scene among the files: its cloud, the first .ply, and its poses,
;; an `images.bin` if there is one. Only those two are fetched, together.
(define (chosen (fetch Fetch) (files (List Chosen))) (→ Scene) (! mut tasks reading)
  (let ((ending (lambda (suffix) (find (lambda (file) (suffix? (● file path) suffix)) files))))
    (match (ending ".ply")
      ((Some cloud)
       (match (ending "images.bin")
         ((Some poses)
          (let ((bytes (fetched fetch (list (● cloud address) (● poses address)))))
            (scene-of (● cloud path)
                      (list-ref bytes 0)
                      (told (● poses path) (read-images (list-ref bytes 1))))))
         ((None)
          (scene-of (● cloud path) (list-ref (fetched fetch (list (● cloud address))) 0) (Nil)))))
      ((None) (unreadable (string-append "no .ply among " (show (length files)) " files"))))))

(define (scene-of (path String) (bytes Bytes) (poses (List ColmapImage))) (→ Scene) (! reading)
  (let ((cloud (told path (read-ply bytes 0))))
    (when (= (● cloud count) 0) (unreadable (string-append path ": no gaussians")))
    (new Scene (cloud cloud) (poses poses))))

;; What a file read as, or the refusal that names it.
(define (told (path String) (result (Result T String))) (→ T) (! reading) (∀ (T))
  (match result
    ((Ok value) value)
    ((Err why) (unreadable (string-append path ": " why)))))

;; The bytes at each address, fetched together.
(define (fetched (fetch Fetch) (addresses (List String))) (→ (List Bytes)) (! mut tasks reading)
  (map (lambda (reply)
         (match reply
           ((Ok bytes) bytes)
           ((Err why) (unreadable why))))
       (fetch-all-bytes fetch addresses)))

(define (suffix? (text String) (suffix String)) (→ Bool)
  (and (>= (string-length text) (string-length suffix))
       (string=?
        (substring text (- (string-length text) (string-length suffix)) (string-length text))
        suffix)))

;; ---- Where the view starts ----

;; `m`, column by column, applied to `v`.
(define (turned (m (List F64)) (v (List F64))) (→ (List F64))
  (map (lambda (row)
         (fold-left +
                    0.0
                    (map (lambda (k) (* (list-ref m (+ (* 3 k) row)) (list-ref v k))) (iota 3))))
       (iota 3)))

;; Where the view of a scene turned by `turn` starts: at its first
;; camera, looking where it looked, at a speed that suits where the
;; cameras stood; or, without cameras, back from the middle of the cloud.
;; Whatever places the fly is turned as the cloud is.
(define (start-of (scene Scene) (turn (List F64))) (→ Fly)
  (match (● scene poses)
    ((Cons camera _)
     (fly-toward (over (map (lambda (image) (turned turn (image-center image))) (● scene poses)))
                 (turned turn (image-center camera))
                 (turned turn (list-tail (image-rotation camera) 6))))
    ((Nil) (over (map (lambda (center) (turned turn center)) (centers (● scene cloud)))))))

;; Up to 2,000 of a cloud's centers, evenly through it.
(define (centers (cloud Cloud)) (→ (List (List F64)))
  (let ((step (+ 1 (quotient (● cloud count) 2000))))
    (map (lambda (k) (cloud-center cloud (* k step))) (iota (quotient (● cloud count) step)))))

;; A fly over the box that holds the middle half of the points along
;; each axis: a trained scene's far background, and a few gaussians
;; farther still, would otherwise set its distance and speed.
(define (over (points (List (List F64)))) (→ Fly)
  (let* ((sorted (map (lambda (axis)
                        (list-sort < (map (lambda (point) (list-ref point axis)) points)))
                      (iota 3)))
         (quarter (quotient (length points) 4))
         (at (lambda (k) (map (lambda (values) (list-ref values k)) sorted))))
    (fly-over (at quarter) (at (- (- (length points) 1) quarter)))))

;; ---- The page ----

;; The value the query gives `name`, from after `name=` up to the next
;; `&`, unescaped.
(define (parameter (address String) (name String)) (→ (Option String))
  (match (found address (string-append name "=") 0)
    ((Some at)
     (let ((rest (substring address (+ at (+ 1 (string-length name))) (string-length address))))
       (Some (uri-path (match (string-index rest #\&)
                         ((Some end) (substring rest 0 end))
                         ((None) rest))))))
    ((None) (None))))

(define (found (text String) (part String) (from I64)) (→ (Option I64))
  (cond ((> (+ from (string-length part)) (string-length text)) (None))
        ((string=? (substring text from (+ from (string-length part))) part) (Some from))
        (else (found text part (+ from 1)))))

;; The files the query names, each at its address: `cloud` and `poses`.
(define (query-files (address String)) (→ (List Chosen))
  (concatenate (map (lambda (name)
                      (match (parameter address name)
                        ((Some file) (list (new Chosen (path file) (address file))))
                        ((None) (Nil))))
                    (list "cloud" "poses"))))

(with-page-fetch
 (lambda ()
   (with-page-files
    (lambda ()
      (with-page-dom events
       (lambda ()
         (let* ((format (● (request-device gpu) format))
                (shown (new Shown (splats (standing gpu (rings) 3 format)) (turned (Some 0.0))))
                (fly (fly-over (list -2.5 -1.0 -2.5) (list 2.5 1.0 2.5)))
                (timing (new Pair (first 0) (second 0))))
           (match (query-files (page-address fetch))
             ((Nil) (view-loop gpu dom picker events fetch out shown fly timing format))
             (files (opened gpu dom picker events fetch out shown fly timing format files))))))))))
