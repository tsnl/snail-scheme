;; A glTF scene path traced in the page, flown through with the mouse and
;; keys: a Khronos sample model the page's query names, `?model=Sponza`,
;; or the user's own. Files dropped on the page, or chosen with O (files)
;; or Shift+O (a folder), replace the scene: a .glb, or a .gltf with the
;; files it names, and an .hdr file to light it. `&env=helipad` lights a
;; sample with a sample environment; without one, or with `env=sky`, a
;; drawn sky and sun light it. The samples come from (khronos samples),
;; which links every sample's files, so the page fetches only those of
;; the model and environment it shows. `&eye=x,y,z,yaw,pitch` places the
;; camera; without it, the camera looks at the scene from outside. A page
;; that names no model shows Sponza from inside its atrium, or else
;; FlightHelmet or the first sample fetched, or nothing until files come.
;; Files that cannot be shown leave the view as it was, and the page says
;; why. The frames average while the camera holds still.
(import
 (snail core base)
 (snail core io)
 (snail shell json)
 (snail shell json read)
 (only (snail shell task) tasks)
 (only (snail shell app) next-event FrameEvent InputEvent FilesEvent KeyDown)
 (only (snail shell page) events report-ready)
 (only (snail shell fetch) fetch fetch-bytes page-address)
 (only (snail shell dom) dom document-root set-text)
 (only (snail shell dom page) with-page-dom)
 (snail shell files)
 (snail shell files page)
 (snail shell resource)
 (khronos samples)
 (snail shell fetch page)
 (only (snail shell gpu) gpu request-device current-texture view-of work-done TextureFormat)
 (snail shell graphics pod)
 (snail shell graphics raster)
 (only (snail shell graphics gltf) uri-path reading unreadable attempt-reading)
 (snail shell graphics trace scene)
 (snail shell graphics environment)
 (snail shell graphics trace render)
 (apps viewer fly))

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

(define sponza-eye (→ String) "9,1.6,-0.4,1.5708,0.12")

;; The sample model the page names, or else Sponza, FlightHelmet or the
;; first sample fetched.
(define (model-of (address String)) (→ String) (! reading)
  (match (parameter address "model")
    ((Some model) model)
    ((None)
     (match (filter (lambda (model) (not (null? (sample-model model))))
                    (append (list "Sponza" "FlightHelmet") (sample-models)))
       ((Cons model _) model)
       ((Nil) (unreadable "No sample models are fetched."))))))

;; Where the page's `eye` puts the fly, or Sponza's atrium for Sponza, or
;; else where it was.
(define (eye-of (address String) (model String) (fly Fly)) (→ Fly)
  (match (match (parameter address "eye")
           ((Some eye) (numbers-of eye))
           ((None) (if (string=? model "Sponza") (numbers-of sponza-eye) (None))))
    ((Some eye) (placed fly eye))
    ((None) fly)))

;; Five numbers, as a JSON array reads them.
(define (numbers-of (text String)) (→ (Option (List F64)))
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

(define (view-loop (view (Option View)) (fly Fly) (timing (Pair I32 I32)) (format TextureFormat))
  (→ Unit)
  (! events gpu output-port tasks fetch files dom)
  (match (next-event)
    ((FrameEvent elapsed)
     (match view
       ((Some shown)
        (let ((fly (flown fly elapsed)))
          (let ((shown (View-tracer-set shown (drawn (● shown tracer) fly))))
            (work-done)
            (report-ready)
            (view-loop (Some shown) fly (timed timing elapsed) format))))
       ((None) (report-ready) (view-loop view fly timing format))))
    ((InputEvent (KeyDown 111 shift))
     (open-picker (if shift (Folder) (SomeFiles)))
     (view-loop view fly timing format))
    ((InputEvent input) (view-loop view (steered fly input) timing format))
    ((FilesEvent _) (opened view fly timing format (chosen-files)))
    (_ (view-loop view fly timing format))))

;; A frame drawn into the canvas, from where the fly is.
(define (drawn (tracer Tracer) (fly Fly)) (→ Tracer) (! gpu)
  (let* ((canvas (current-texture))
         (width (● canvas width))
         (height (● canvas height)))
    (draw-traced (resize-tracer tracer width height)
                 (view-of (● canvas texture) 1)
                 (fly-camera fly (/ (i32->f64 width) (i32->f64 (max 1 height))))
                 (fly-spread height)
                 (fly-exposure fly))))

;; Frames and milliseconds since the last report, which comes every two
;; seconds.
(define (timed (timing (Pair I32 I32)) (elapsed I32)) (→ (Pair I32 I32)) (! output-port)
  (let ((frames (+ 1 (● timing first))) (total (+ elapsed (● timing second))))
    (if (< total 2000)
        (new Pair (first frames) (second total))
        (begin
          (write-line (string-append "frames: " (show frames) " in " (show total) " ms"))
          (new Pair (first 0) (second 0))))))

;; ---- The user's files ----

;; The view of the files the user chose, the fly looking at a new scene
;; from outside; or the view as it was, and why, when they cannot be
;; shown.
(define (opened (view (Option View))
                (fly Fly)
                (timing (Pair I32 I32))
                (format TextureFormat)
                (files (List Chosen)))
  (→ Unit)
  (! events gpu output-port tasks fetch files dom)
  (set-text (document-root) "Loading…")
  (match (attempt-reading (lambda () (chosen view files)))
    ((Ok replacing)
     (set-text (document-root) "")
     (view-loop (Some (shown view (● replacing first) (● replacing second) format))
                (match (● replacing first)
                  ((Some scene)
                   (Fly-stops-set (fly-over (● scene low) (● scene high)) (● fly stops)))
                  ((None) fly))
                timing
                format))
    ((Err why) (say why) (view-loop view fly timing format))))

;; What the page says under the view, and the console with it.
(define (say (message String)) (→ Unit) (! dom output-port)
  (set-text (document-root) message)
  (write-line message))

;; What the files replace: the scene, by the model among them, and the
;; light, by the HDR file among them. Files with neither refuse, as does
;; a light with no view to light. The light's file is read before the
;; scene is loaded, and nothing after the scene refuses, so files refused
;; leave nothing on the device.
(define (chosen (view (Option View)) (files (List Chosen)))
  (→ (Pair (Option Scene) (Option Environment)))
  (! gpu output-port tasks fetch reading)
  (let ((model (outermost (ending files (list ".glb" ".gltf"))))
        (light (outermost (ending files (list ".hdr")))))
    (when (match (new Pair (first model) (second (new Pair (first light) (second view))))
            ((Pair (Some _) _) #f)
            ((Pair (None) (Pair (Some _) (Some _))) #f)
            (_ #t))
      (unreadable (string-append "nothing to show among " (show (length files)) " files")))
    (let* ((hdr (within light (lambda (path) (radiance path (chosen-bytes files path)))))
           (scene (within model
                          (lambda (path)
                            (loaded-scene (lambda ((paths (List String)))
                                            (→ (List Bytes))
                                            (! fetch tasks reading)
                                            (map (lambda (path) (chosen-bytes files path)) paths))
                                          path)))))
      (new Pair (first scene) (second (within hdr hdr-light))))))

;; `f` of what an option holds.
(define (within (option (Option A)) (f (Fn A → B ! e))) (→ (Option B)) (! e) (∀ (A B e))
  (match option
    ((Some value) (Some (f value)))
    ((None) (None))))

;; An HDR file read, which a file that is not one refuses.
(define (radiance (name String) (bytes Bytes)) (→ Hdr) (! reading)
  (match (read-hdr bytes)
    ((Ok hdr) hdr)
    ((Err why) (unreadable (string-append name ": " why)))))

(define (hdr-light (hdr Hdr)) (→ Environment) (! gpu) (hdr-environment hdr 4096))

;; The view with a new scene, a new light, or both: its tracer remade
;; from the old one, whose scene or light, where replaced, is let go. A
;; first view needs a scene, and without a light has the drawn sky's.
(define (shown (view (Option View))
               (scene (Option Scene))
               (light (Option Environment))
               (format TextureFormat))
  (→ View)
  (! gpu)
  (match view
    ((Some old)
     (let* ((scene (match scene
                     ((Some scene) (release-scene (● old scene)) scene)
                     ((None) (● old scene))))
            (environment (match light
                           ((Some light) (release-environment (● old environment)) light)
                           ((None) (● old environment)))))
       (new View
         (scene scene)
         (environment environment)
         (tracer (retrace (● old tracer) scene environment)))))
    ((None)
     (let ((canvas (current-texture))
           (scene (match scene
                    ((Some scene) scene)
                    ((None) (panic "internal error: a first view without a scene"))))
           (environment (match light
                          ((Some light) light)
                          ((None) (sky-environment sky 4096)))))
       (new View
         (scene scene)
         (environment environment)
         (tracer
          (make-tracer scene environment format (● canvas width) (● canvas height) layer-size)))))))



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

(define (chosen-bytes (files (List Chosen)) (path String)) (→ Bytes) (! fetch tasks reading)
  (match (filter (lambda (file) (string=? (● file path) path)) files)
    ((Cons file _)
     (match (fetch-bytes (● file address))
       ((Ok bytes) bytes)
       ((Err why) (unreadable (string-append path ": " why)))))
    ((Nil) (unreadable (string-append path " is not among the files chosen")))))

;; A scene, and a line saying how large it is.
(define (loaded-scene (read (Fn (List String) → (List Bytes) ! reading e)) (path String))
  (→ Scene)
  (! gpu output-port tasks reading e)
  (∀ (e))
  (let ((scene (load-scene read path layer-size)))
    (write-line (string-append "scene: "
                               (show (● scene vertex-count))
                               " vertices, "
                               (show (● scene triangle-count))
                               " triangles, from " (string-join (map show (● scene low)) " ")
                               " to " (string-join (map show (● scene high)) " ")))
    scene))

;; ---- The page ----

(with-page-fetch
 (lambda ()
   (with-page-files
    (lambda ()
      (with-page-dom
       (lambda ()
         (let ((format (● (request-device) format)) (timing (new Pair (first 0) (second 0))))
           (match (attempt-reading (lambda () (sample-view (page-address) format)))
             ((Ok sample) (view-loop (Some (● sample first)) (● sample second) timing format))
             ((Err why)
              (say why)
              (view-loop (None)
                         (fly-over (list -1.0 -1.0 -1.0) (list 1.0 1.0 1.0))
                         timing
                         format))))))))))

;; The view of the sample the page names, in the sample environment it
;; names or the drawn sky, and the fly looking at it.
(define (sample-view (address String) (format TextureFormat))
  (→ (Pair View Fly))
  (! gpu output-port resource tasks reading)
  (let* ((model (model-of address))
         (hdr (sample-light (parameter address "env")))
         (scene (model-scene model)))
    (new Pair
      (first (shown (None) (Some scene) (within hdr hdr-light) format))
      (second (eye-of address model (fly-over (● scene low) (● scene high)))))))

(define (placed (fly Fly) (eye (List F64))) (→ Fly)
  (new Fly
    (x (list-ref eye 0))
    (y (list-ref eye 1))
    (z (list-ref eye 2))
    (yaw (list-ref eye 3))
    (pitch (list-ref eye 4))
    (held (Nil))
    (drag (None))
    (speed (● fly speed))
    (stops (● fly stops))))

;; ---- Samples ----

;; The sample model `name`, its files read together as the scene asks.
(define (model-scene (name String)) (→ Scene) (! gpu output-port resource tasks reading)
  (let ((files (sample-model name)))
    (match files
      ((Nil) (unreadable (string-append "There is no sample model " name ".")))
      ((Cons entry _)
       (loaded-scene (lambda ((paths (List String))) (→ (List Bytes)) (! resource tasks reading)
                       (read-resources (map (lambda (path) (model-file name files path)) paths)))
                     (● entry first))))))

(define (model-file (name String) (files (List (Pair String Resource))) (path String))
  (→ Resource)
  (! reading)
  (match (assoc-ref files path)
    ((Some file) file)
    ((None) (unreadable (string-append name " has no file " path)))))

;; The file of the sample environment `env=` names; none for the drawn
;; sky.
(define (sample-light (name (Option String))) (→ (Option Hdr)) (! resource tasks reading)
  (match name
    ((Some "sky") (None))
    ((Some name)
     (match (sample-environment name)
       ((Some file) (Some (radiance name (read-resource file))))
       ((None) (unreadable (string-append "There is no sample environment " name ".")))))
    ((None) (None))))
