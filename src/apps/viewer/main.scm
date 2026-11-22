;; A glTF scene path traced in the page, flown through with the mouse and
;; keys. The page ships no scene: it shows the files its user chooses, a
;; .glb, or a .gltf with the files it names, and an .hdr file to light
;; it; without one, a drawn sky and sun light it. Files come dropped on
;; the page, or chosen with O (files) or Shift+O (a folder). A link
;; dropped on the page is a file at its address, and a .gltf at an
;; address names its files relative to it, so the page's sample links,
;; to Khronos's sample models and Poly Haven's environments, are fetched
;; by the browser from where they are published. The page's query chooses
;; the same way: `?model=ADDRESS&env=ADDRESS`, and `&eye=x,y,z,yaw,pitch`
;; places the camera; without it, the camera looks at the scene from
;; outside. Files that cannot be shown leave the view as it was, and the
;; page says why. The frames average while the camera holds still.
(import
 (snail core base)
 (snail core io)
 (snail shell json)
 (snail shell json read)
 (only (snail shell app) next-event FrameEvent InputEvent FilesEvent KeyDown)
 (only (snail shell page) Events report-ready)
 (only (snail shell fetch) Fetch fetch-all-bytes page-address)
 (only (snail shell dom) Dom document-root set-text)
 (snail shell files)
 (only (snail shell gpu) Gpu request-device current-texture view-of work-done TextureFormat)
 (snail shell graphics pod)
 (snail shell graphics raster)
 (only (snail shell graphics gltf) uri-path unreadable attempt-reading)
 (snail shell graphics trace scene)
 (snail shell graphics environment)
 (snail shell graphics trace render)
 (snail shell graphics fly))

(define layer-size (→ I32) 1024)

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

;; The files the query names, each at its address: `model` and `env`.
(define (query-files (address String)) (→ (List Chosen))
  (concatenate (map (lambda (name)
                      (match (parameter address name)
                        ((Some file) (list (new Chosen (path file) (address file))))
                        ((None) (Nil))))
                    (list "model" "env"))))

;; Where the query's `eye` puts the camera: five numbers, as a JSON array
;; reads them.
(define (query-eye (address String)) (→ (Option (List F64)))
  (match (parameter address "eye")
    ((Some text)
     (match (string->json (string-append "[" text "]"))
       ((Some (JsonArray values))
        (if (= (length values) 5)
            (Some (map (lambda (value)
                         (match value
                           ((JsonInteger n) (i64->f64 n))
                           ((JsonNumber n) n)
                           (_ 0.0)))
                       values))
            (None)))
       (_ (None))))
    ((None) (None))))

(define (found (text String) (part String) (from I64)) (→ (Option I64))
  (cond ((> (+ from (string-length part)) (string-length text)) (None))
        ((string=? (substring text from (+ from (string-length part))) part) (Some from))
        (else (found text part (+ from 1)))))

(define sky
  (→ Sky)
  (new Sky
    (sun (unit 0.3 1.0 0.25 0.99996))
    (sun-light (new Vec4f (x 10.0) (y 9.5) (z 8.5) (w 0.0)))
    (zenith (new Vec4f (x 0.25) (y 0.45) (z 0.9) (w 1.5)))
    (horizon (new Vec4f (x 0.75) (y 0.82) (z 0.95) (w 1.5)))
    (ground (new Vec4f (x 0.3) (y 0.27) (z 0.24) (w 1.0)))))

(define (unit (x F64) (y F64) (z F64) (w F64)) (→ Vec4f)
  (let ((length (sqrt (+ (* x x) (+ (* y y) (* z z))))))
    (new Vec4f
      (x (f64->f32 (/ x length)))
      (y (f64->f32 (/ y length)))
      (z (f64->f32 (/ z length)))
      (w (f64->f32 w)))))

;; ---- The view ----

;; The scene shown, the light it is shown in, and the tracer drawing it.
(record View
  ((scene Scene)
   (environment Environment)
   (tracer Tracer)))

;; The page's events, each answered with the next view. The view, the fly
;; and the frame count are what change from one event to the next; what
;; the loop reaches the page through, it is handed once.
(define (view-loop (gpu Gpu)
                   (dom Dom)
                   (picker FilePicker)
                   (events Events)
                   (fetch Fetch)
                   (out OutputPort)
                   (format TextureFormat)
                   (view (Option View))
                   (fly Fly))
  (→ Unit)
  (let loop ((view view) (fly fly) (timing (new Pair (first 0) (second 0))))
    (match (next-event events)
      ((FrameEvent elapsed)
       (match view
         ((Some shown)
          (let* ((fly (flown fly elapsed))
                 (shown (View-tracer-set shown (drawn gpu (● shown tracer) fly))))
            (work-done gpu)
            (report-ready events)
            (loop (Some shown) fly (timed out timing elapsed))))
         ((None)
          (report-ready events)
          (loop view fly timing))))
      ((InputEvent (KeyDown 111 shift))
       (open-picker picker (if shift (Folder) (SomeFiles)))
       (loop view fly timing))
      ((InputEvent input) (loop view (steered fly input) timing))
      ((FilesEvent _)
       (match (opened gpu dom fetch out format view fly (chosen-files picker) (None))
         ((Pair view fly) (loop view fly timing))))
      (_ (loop view fly timing)))))

;; A frame drawn into the canvas, from where the fly is.
(define (drawn (gpu Gpu) (tracer Tracer) (fly Fly)) (→ Tracer)
  (let* ((canvas (current-texture gpu))
         (width (● canvas width))
         (height (● canvas height)))
    (draw-traced gpu (resize-tracer gpu tracer width height)
                 (view-of gpu (● canvas texture) 1)
                 (fly-camera fly (/ (i32->f64 width) (i32->f64 (max 1 height))))
                 (fly-spread height)
                 (fly-exposure fly))))

;; Frames and milliseconds since the last report, which comes every two
;; seconds.
(define (timed (out OutputPort) (timing (Pair I32 I32)) (elapsed I32)) (→ (Pair I32 I32))
  (let ((frames (+ 1 (● timing first))) (total (+ elapsed (● timing second))))
    (if (< total 2000)
        (new Pair (first frames) (second total))
        (begin
          (write-line out (string-append "frames: " (show frames) " in " (show total) " ms"))
          (new Pair (first 0) (second 0))))))

;; ---- The files chosen ----

;; The view of the files chosen, the fly looking at a new scene from
;; `eye` or else from outside; or the view as it was, and why, when they
;; cannot be shown. The loop waits here, so one choice is read at a time,
;; and one that arrives meanwhile is read next.
(define (opened (gpu Gpu)
                (dom Dom)
                (fetch Fetch)
                (out OutputPort)
                (format TextureFormat)
                (view (Option View))
                (fly Fly)
                (files (List Chosen))
                (eye (Option (List F64))))
  (→ (Pair (Option View) Fly))
  (set-text dom (document-root dom) "Loading…")
  (match (attempt-reading (lambda () (chosen gpu fetch out view files)))
    ((Ok replacing)
     (set-text dom (document-root dom) "")
     (new Pair
       (first (Some (shown gpu view (● replacing first) (● replacing second) format)))
       (second (match (● replacing first)
                 ((Some scene)
                  (let ((over (Fly-stops-set (fly-over (● scene low) (● scene high))
                                             (● fly stops))))
                    (match eye
                      ((Some eye) (fly-at over eye))
                      ((None) over))))
                 ((None) fly)))))
    ((Err why)
     (say dom out why)
     (new Pair (first view) (second fly)))))

;; What the page says under the view, and the console with it.
(define (say (dom Dom) (out OutputPort) (message String)) (→ Unit)
  (set-text dom (document-root dom) message)
  (write-line out message))

;; What the files replace: the scene, by the model among them, and the
;; light, by the HDR file among them. Files with neither refuse, as does
;; a light with no view to light. The light's file is read before the
;; scene is loaded, and nothing after the scene refuses, so files refused
;; leave nothing on the device.
(define (chosen (gpu Gpu) (fetch Fetch) (out OutputPort) (view (Option View)) (files (List Chosen)))
  (→ (Pair (Option Scene) (Option Environment)))
  (let ((model (outermost (ending files (list ".glb" ".gltf"))))
        (light (outermost (ending files (list ".hdr")))))
    (when (and (none? model) (or (none? light) (none? view)))
      (unreadable (string-append "nothing to show among " (show (length files)) " files")))
    (let* ((hdr (within light
                        (lambda (path)
                          (radiance path (list-ref (read fetch files path (list path)) 0)))))
           (scene (within model
                          (lambda (path)
                            (loaded-scene gpu out (lambda ((paths (List String)))
                                                    (→ (List Bytes))
                                                    (read fetch files path paths))
                                          path)))))
      (new Pair (first scene) (second (within hdr (lambda (hdr) (hdr-light gpu hdr))))))))

;; The bytes of the paths that the file at `top` names, fetched together.
(define (read (fetch Fetch) (files (List Chosen)) (top String) (paths (List String)))
  (→ (List Bytes))
  (fetched fetch (map (lambda (path) (address-of files top path)) paths)))

;; Where a path that the file at `top` names is fetched from: a file
;; chosen, at its address; or, when `top` is a link, the path itself,
;; since a scene at an address names its files relative to it. A scene
;; among the user's files reads nothing they did not choose.
(define (address-of (files (List Chosen)) (top String) (path String)) (→ String)
  (match (find (lambda (file) (string=? (● file path) path)) files)
    ((Some file) (● file address))
    ((None)
     (if (any? (lambda (file) (and (string=? (● file path) top) (string=? (● file address) top)))
               files)
         path
         (unreadable (string-append path " is not among the files chosen"))))))

;; The bytes at each address, fetched together.
(define (fetched (fetch Fetch) (addresses (List String))) (→ (List Bytes))
  (map (lambda (reply)
         (match reply
           ((Ok bytes) bytes)
           ((Err why) (unreadable why))))
       (fetch-all-bytes fetch addresses)))

(define (none? (option (Option A))) (→ Bool) (∀ (A))
  (match option
    ((Some _) #f)
    ((None) #t)))

;; `f` of what an option holds.
(define (within (option (Option A)) (f (Fn A → B))) (→ (Option B)) (∀ (A B))
  (match option
    ((Some value) (Some (f value)))
    ((None) (None))))

;; An HDR file read, which a file that is not one refuses.
(define (radiance (name String) (bytes Bytes)) (→ Hdr)
  (match (read-hdr bytes)
    ((Ok hdr) hdr)
    ((Err why) (unreadable (string-append name ": " why)))))

(define (hdr-light (gpu Gpu) (hdr Hdr)) (→ Environment) (hdr-environment gpu hdr 4096))

;; The view with a new scene, a new light, or both: its tracer remade
;; from the old one, whose scene or light, where replaced, is let go. A
;; first view needs a scene, and without a light has the drawn sky's.
(define (shown (gpu Gpu) (view (Option View))
               (scene (Option Scene))
               (light (Option Environment))
               (format TextureFormat))
  (→ View)
  (match view
    ((Some old)
     (let* ((scene (match scene
                     ((Some scene) (release-scene gpu (● old scene)) scene)
                     ((None) (● old scene))))
            (environment (match light
                           ((Some light) (release-environment gpu (● old environment)) light)
                           ((None) (● old environment)))))
       (new View
         (scene scene)
         (environment environment)
         (tracer (retrace gpu (● old tracer) scene environment)))))
    ((None)
     (let ((canvas (current-texture gpu))
           (scene (match scene
                    ((Some scene) scene)
                    ((None) (panic "internal error: a first view without a scene"))))
           (environment (match light
                          ((Some light) light)
                          ((None) (sky-environment gpu sky 4096)))))
       (new View
         (scene scene)
         (environment environment)
         (tracer
          (make-tracer gpu
                       scene
                       environment
                       format
                       (● canvas width)
                       (● canvas height)
                       layer-size)))))))



;; The paths of the files with one of the suffixes, in any case.
(define (ending (files (List Chosen)) (suffixes (List String))) (→ (List String))
  (filter (lambda (path) (not (null? (filter (lambda (suffix) (suffix? path suffix)) suffixes))))
          (map (lambda (file) (● file path)) files)))

(define (suffix? (text String) (suffix String)) (→ Bool)
  (and (>= (string-length text) (string-length suffix))
       (string=? (list->string (map lowered
                                    (string->list (substring text
                                                             (- (string-length text)
                                                                (string-length suffix))
                                                             (string-length text)))))
                 suffix)))

(define (lowered (char Char)) (→ Char)
  (let ((code (char->integer char)))
    (if (and (>= code 65) (<= code 90)) (integer->char (+ code 32)) char)))

;; The path in the fewest folders, the first of those.
(define (outermost (paths (List String))) (→ (Option String))
  (fold-left (lambda (best path)
               (match best
                 ((Some other) (if (< (depth path) (depth other)) (Some path) best))
                 ((None) (Some path))))
             (None)
             paths))

(define (depth (path String)) (→ I64)
  (length (filter (lambda (char) (char=? char #\/)) (string->list path))))



;; A scene, and a line saying how large it is.
(define (loaded-scene (gpu Gpu)
                      (out OutputPort)
                      (read (Fn (List String) → (List Bytes)))
                      (path String))
  (→ Scene)
  (let ((scene (load-scene gpu read path layer-size)))
    (write-line out (string-append "scene: "
                                   (show (● scene vertex-count))
                                   " vertices, "
                                   (show (● scene triangle-count))
                                   " triangles, from " (string-join (map show (● scene low)) " ")
                                   " to " (string-join (map show (● scene high)) " ")))
    scene))

;; ---- The page ----

(define (main (gpu Gpu)
              (dom Dom)
              (fetch Fetch)
              (picker FilePicker)
              (events Events)
              (out OutputPort))
  (→ Unit)
  (let ((format (● (request-device gpu) format))
        (outside (fly-over (list -1.0 -1.0 -1.0) (list 1.0 1.0 1.0)))
        (address (page-address fetch)))
    (match (match (query-files address)
             ((Nil) (new Pair (first (None)) (second outside)))
             (files (opened gpu dom fetch out format (None) outside files (query-eye address))))
      ((Pair view fly) (view-loop gpu dom picker events fetch out format view fly)))))
