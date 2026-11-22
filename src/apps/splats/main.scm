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
;;
;; T draws the splats tile by tile, by the renderer training descends
;; through ((snail shell graphics splat-view)), and again as quads. Every
;; two seconds the console has the frame rate and, where the device has
;; timestamps, one frame's compute and render passes timed on it.
(import
 (snail core base)
 (snail core io)
 (only (snail shell app) next-event FrameEvent InputEvent FilesEvent KeyDown)
 (only (snail shell page) Events)
 (only (snail shell fetch) Fetch)
 (only (snail shell dom) Dom)
 (snail shell files)
 (snail shell gpu)
 (snail shell graphics pod)
 (only (snail shell graphics gltf) uri-path unreadable attempt-reading)
 (snail shell graphics colmap)
 (snail shell graphics ply)
 (snail shell graphics splat)
 (snail shell graphics splat-view)
 (snail shell graphics fly)
 (apps splats rings))

;; ---- The view ----

;; What is drawn: the one splats on the device; the seconds the rings
;; have turned, which pose them each frame, or none for a file's cloud,
;; which is posed once; whether they are drawn tile by tile, by the
;; renderer training descends through, rather than as quads, which T
;; toggles; and that renderer's view of them, made for the canvas's size.
(record Shown
  ((splats Splats)
   (turned (Option F64))
   (tiled Bool)
   (view (Option SplatView))))

;; The page's events, each answered with the next view. The view, the fly
;; and the frame count are what change from one event to the next; what
;; the loop reaches the page through, it is handed once.
(define (view-loop (events Events)
                   (dom Dom)
                   (picker FilePicker)
                   (fetch Fetch)
                   (out OutputPort)
                   (gpu Gpu)
                   (info DeviceInfo)
                   (shown Shown)
                   (fly Fly))
  (→ Unit)
  (let loop ((shown shown) (fly fly) (timing (new Pair (first 0) (second 0))))
    (match (next-event events)
      ((FrameEvent elapsed)
       (let* ((canvas ((● gpu current-texture)))
              (shown (fitted gpu (turning gpu shown elapsed) canvas (● info format)))
              (fly (flown fly elapsed))
              (timing (counted timing elapsed))
              (due (>= (● timing second) 2000)))
         (if due
             (reported out gpu shown canvas fly timing info)
             (submit-frame gpu shown canvas fly))
         ((● gpu work-done))
         ((● events report-ready))
         (loop shown fly (if due (new Pair (first 0) (second 0)) timing))))
      ((InputEvent (KeyDown 111 _))
       ((● picker open-picker) (SomeFiles))
       (loop shown fly timing))
      ((InputEvent (KeyDown 116 _)) (loop (Shown-tiled-set shown (not (● shown tiled))) fly timing))
      ((InputEvent input) (loop shown (steered fly input) timing))
      ((FilesEvent _)
       (match (opened dom fetch out gpu info shown fly ((● picker chosen-files)))
         ((Pair shown fly) (loop shown fly timing))))
      (_ (loop shown fly timing)))))

;; The rings posed where `elapsed` more milliseconds turn them.
(define (turning (gpu Gpu) (shown Shown) (elapsed I32)) (→ Shown)
  (match (● shown turned)
    ((Some seconds)
     (let ((now (+ seconds (/ (i32->f64 elapsed) 1000.0))))
       (write-transforms gpu (● shown splats) (ring-poses now))
       (Shown-turned-set shown (Some now))))
    ((None) shown)))

;; The splats with a view made for the canvas's size while they are drawn
;; tile by tile, made again when the canvas changes size, and with none
;; while they are drawn as quads.
(define (fitted (gpu Gpu) (shown Shown) (canvas Image) (format TextureFormat)) (→ Shown)
  (match (● shown view)
    ((Some view)
     (if (and (● shown tiled)
              (= (● view width) (i32->i64 (● canvas width)))
              (= (● view height) (i32->i64 (● canvas height))))
         shown
         (begin
           (release-splat-view gpu view)
           (fitted gpu (Shown-view-set shown (None)) canvas format))))
    ((None)
     (if (● shown tiled)
         (Shown-view-set shown
                         (Some (make-splat-view gpu (● shown splats)
                                                format
                                                (i32->i64 (● canvas width))
                                                (i32->i64 (● canvas height))
                                                (* 4 (● shown splats capacity)))))
         shown))))

;; The splats drawn into the canvas from where the fly is, as quads or tile
;; by tile, each pass timed into the queries when there are some: the
;; compute pass into 0 and 1, the canvas's into 2 and 3.
(define (frame (gpu Gpu) (shown Shown) (canvas Image) (fly Fly) (queries (Option GpuQuerySet)))
  (→ GpuCommandEncoder)
  (let* ((camera (splat-camera (fly-eye fly)
                               (fly-target fly)
                               (new Vec3f (x 0.0) (y 1.0) (z 0.0))
                               fly-fov
                               (● canvas width)
                               (● canvas height)))
         (encoder ((● gpu create-command-encoder)))
         (compute (compute-pass gpu encoder queries)))
    (match (● shown view)
      ((Some view) (write-view-camera gpu view camera) (encode-splat-view gpu compute view))
      ((None) (sort-splats gpu compute (● shown splats) camera)))
    ((● gpu end-compute-pass) compute)
    (let ((pass (canvas-pass gpu encoder canvas queries)))
      (match (● shown view)
        ((Some view) (present-splat-view gpu pass view))
        ((None) (draw-splats gpu pass (● shown splats))))
      ((● gpu end-pass) pass))
    encoder))

(define (submit-frame (gpu Gpu) (shown Shown) (canvas Image) (fly Fly)) (→ Unit)
  ((● gpu submit) (list ((● gpu finish) (frame gpu shown canvas fly (None))))))

(define (compute-pass (gpu Gpu) (encoder GpuCommandEncoder) (queries (Option GpuQuerySet)))
  (→ GpuComputePass)
  (match queries
    ((Some q)
     ((● gpu begin-timed-compute-pass)
      encoder
      (new TimestampWrites (query-set q) (beginning 0) (end 1))))
    ((None) ((● gpu begin-compute-pass) encoder))))

;; The canvas, cleared to the background.
(define (canvas-pass (gpu Gpu)
                     (encoder GpuCommandEncoder)
                     (canvas Image)
                     (queries (Option GpuQuerySet)))
  (→ GpuRenderPass)
  (let ((descriptor (new RenderPassDescriptor
                      (colors (list (Some (new ColorAttachment
                                            (view (view-of gpu (● canvas texture) 1))
                                            (load (Clear (new Color
                                                           (red 0.02)
                                                           (green 0.02)
                                                           (blue 0.03)
                                                           (alpha 1.0))))
                                            (store #t)))))
                      (depth (None)))))
    (match queries
      ((Some q)
       ((● gpu begin-timed-render-pass) encoder
        descriptor
        (new TimestampWrites (query-set q) (beginning 2) (end 3))))
      ((None) ((● gpu begin-render-pass) encoder descriptor)))))

;; Frames and milliseconds since the last report.
(define (counted (timing (Pair I32 I32)) (elapsed I32)) (→ (Pair I32 I32))
  (new Pair (first (+ 1 (● timing first))) (second (+ elapsed (● timing second)))))

;; Every two seconds, the frames and milliseconds since the last report,
;; and, where the device has timestamps, this frame's two passes' times
;; on it. A page's times are rounded to 100 μs.
(define (reported (out OutputPort)
                  (gpu Gpu)
                  (shown Shown)
                  (canvas Image)
                  (fly Fly)
                  (timing (Pair I32 I32))
                  (info DeviceInfo))
  (→ Unit)
  (let ((line
         (string-append "frames: " (show (● timing first)) " in " (show (● timing second)) " ms")))
    (if (member? "timestamp-query" (● info features))
        (let* ((queries
                ((● gpu create-query-set) (new QuerySetDescriptor (label "frame") (count 4))))
               (times (submit-timed gpu (frame gpu shown canvas fly (Some queries)) queries 4)))
          ((● gpu destroy) (QuerySetObject queries))
          (write-line out (string-append line
                                         "; on the device "
                                         (milliseconds (elapsed-seconds times 0 1))
                                         " + "
                                         (milliseconds (elapsed-seconds times 2 3))
                                         " ms "
                                         (if (● shown tiled) "tile by tile" "as quads"))))
        (begin
          (submit-frame gpu shown canvas fly)
          (write-line out line)))))

(define (milliseconds (seconds F64)) (→ String)
  (f64->string (/ (round (* seconds 100000.0)) 100.0)))

;; A cloud on the device, with `rows` rows of transforms to pose it by.
(define (standing (gpu Gpu) (cloud Cloud) (rows I64) (format TextureFormat)) (→ Splats)
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
(define (opened (dom Dom)
                (fetch Fetch)
                (out OutputPort)
                (gpu Gpu)
                (info DeviceInfo)
                (shown Shown)
                (fly Fly)
                (files (List Chosen)))
  (→ (Pair Shown Fly))
  ((● dom set-text) ((● dom document-root)) "Loading…")
  (match (attempt-reading (lambda () (chosen fetch files)))
    ((Ok scene)
     (match (● shown view)
       ((Some view) (release-splat-view gpu view))
       ((None) (unit)))
     (release-splats gpu (● shown splats))
     (say dom out (string-append (show (● (● scene cloud) count)) " gaussians"))
     (let ((turn (upright (poses-up (● scene poses))))
           (splats (standing gpu (● scene cloud) 1 (● info format))))
       (write-transforms gpu splats (list (pose turn 0.0 0.0 0.0)))
       (new Pair
         (first (new Shown
                  (splats splats)
                  (turned (None))
                  (tiled (● shown tiled))
                  (view (None))))
         (second (start-of scene turn)))))
    ((Err why)
     (say dom out why)
     (new Pair (first shown) (second fly)))))

;; What the page says beside the view, and the console with it.
(define (say (dom Dom) (out OutputPort) (message String)) (→ Unit)
  ((● dom set-text) ((● dom document-root)) message)
  (write-line out message))

;; The scene among the files: its cloud, the first .ply, and its poses,
;; an `images.bin` if there is one. Only those two are fetched, together.
(define (chosen (fetch Fetch) (files (List Chosen))) (→ Scene)
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

(define (scene-of (path String) (bytes Bytes) (poses (List ColmapImage))) (→ Scene)
  (let ((cloud (told path (read-ply bytes 0))))
    (when (= (● cloud count) 0) (unreadable (string-append path ": no gaussians")))
    (new Scene (cloud cloud) (poses poses))))

;; What a file read as, or the refusal that names it.
(define (told (path String) (result (Result T String))) (→ T) (∀ (T))
  (match result
    ((Ok value) value)
    ((Err why) (unreadable (string-append path ": " why)))))

;; The bytes at each address, fetched together.
(define (fetched (fetch Fetch) (addresses (List String))) (→ (List Bytes))
  (map (lambda (reply)
         (match reply
           ((Ok bytes) bytes)
           ((Err why) (unreadable why))))
       ((● fetch fetch-all-bytes) addresses)))

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

(define (main (events Events)
              (dom Dom)
              (picker FilePicker)
              (fetch Fetch)
              (out OutputPort)
              (gpu Gpu))
  (→ Unit)
  (let* ((info ((● gpu request-device)))
         (rings (new Shown
                  (splats (standing gpu (rings) 3 (● info format)))
                  (turned (Some 0.0))
                  (tiled #f)
                  (view (None))))
         (over-rings (fly-over (list -2.5 -1.0 -2.5) (list 2.5 1.0 2.5))))
    (match (match (query-files ((● fetch page-address)))
             ((Nil) (new Pair (first rings) (second over-rings)))
             (files (opened dom fetch out gpu info rings over-rings files)))
      ((Pair shown fly) (view-loop events dom picker fetch out gpu info shown fly))))
  (unit))
