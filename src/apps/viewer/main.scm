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
;; FlightHelmet or the first sample fetched, or nothing until files come. The frames average while
;; the camera holds still.
(import
 (snail core base)
 (snail core io)
 (snail shell json)
 (snail shell json read)
 (only (snail shell task) tasks)
 (only (snail shell app) next-event FrameEvent InputEvent FilesEvent KeyDown)
 (only (snail shell page) events report-ready)
 (only (snail shell fetch) fetch fetch-bytes page-address)
 (snail shell files)
 (snail shell files page)
 (snail shell resource)
 (khronos samples)
 (snail shell fetch page)
 (only (snail shell gpu) gpu request-device current-texture view-of work-done TextureFormat)
 (snail shell graphics pod)
 (snail shell graphics raster)
 (only (snail shell graphics gltf) uri-path)
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
;; first sample fetched, and the eye the page names, or Sponza's atrium
;; for Sponza.
(define (model-of (address String)) (→ (Option (Pair String (Option String))))
  (match (match (parameter address "model")
           ((Some model) (Some model))
           ((None)
            (match (filter (lambda (model) (not (null? (sample-model model))))
                           (append (list "Sponza" "FlightHelmet") (sample-models)))
              ((Cons model _) (Some model))
              ((Nil) (None)))))
    ((Some model)
     (Some (new Pair
             (first model)
             (second (match (parameter address "eye")
                       ((Some eye) (Some eye))
                       ((None) (if (string=? model "Sponza") (Some sponza-eye) (None))))))))
    ((None) (None))))

;; Five numbers, as a JSON array reads them.
(define (eye-of (text String)) (→ (Option (List F64)))
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
  (! events gpu output-port tasks fetch files)
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

;; The view of the files the user chose: the model among them, lit by
;; the HDR file among them or by the light it had, the fly looking at it
;; from outside; or the view lit by the HDR file alone. Choosing no model
;; and no light changes nothing.
(define (opened (view (Option View))
                (fly Fly)
                (timing (Pair I32 I32))
                (format TextureFormat)
                (files (List Chosen)))
  (→ Unit)
  (! events gpu output-port tasks fetch files)
  (let ((model (outermost (ending files (list ".glb" ".gltf"))))
        (light (outermost (ending files (list ".hdr")))))
    (match model
      ((Some path)
       (let ((scene (loaded-scene (lambda ((paths (List String))) (→ (List Bytes)) (! fetch tasks)
                                    (map (lambda (path) (chosen-bytes files path)) paths))
                                  path)))
         (view-loop (Some (shown view (Some scene) (user-light files light) format))
                    (Fly-stops-set (fly-over (● scene low) (● scene high)) (● fly stops))
                    timing
                    format)))
      ((None)
       (match (match view
                ((Some _) light)
                ((None) (None)))
         ((Some _)
          (view-loop (Some (shown view (None) (user-light files light) format)) fly timing format))
         ((None)
          (write-line
           (string-append "nothing to show among " (show (length files)) " files"))
          (view-loop view fly timing format)))))))

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

;; The HDR file's light, if the user chose one.
(define (user-light (files (List Chosen)) (light (Option String)))
  (→ (Option Environment))
  (! gpu tasks fetch)
  (match light
    ((Some path)
     (match (hdr-environment (chosen-bytes files path) 4096)
       ((Ok environment) (Some environment))
       ((Err why) (panic (string-append path (string-append ": " why))))))
    ((None) (None))))

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

(define (chosen-bytes (files (List Chosen)) (path String)) (→ Bytes) (! fetch tasks)
  (match (filter (lambda (file) (string=? (● file path) path)) files)
    ((Cons file _)
     (match (fetch-bytes (● file address))
       ((Ok bytes) bytes)
       ((Err why) (panic (string-append path (string-append ": " why))))))
    ((Nil) (panic (string-append "no file " (string-append path " was chosen"))))))

;; A scene, and a line saying how large it is.
(define (loaded-scene (read (Fn (List String) → (List Bytes) ! e)) (path String))
  (→ Scene)
  (! gpu output-port tasks e)
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
      (let ((format (● (request-device) format)))
        (match (model-of (page-address))
          ((Some chosen)
           (let* ((scene (model-scene (● chosen first)))
                  (over (fly-over (● scene low) (● scene high))))
             (view-loop (Some (shown (None)
                                     (Some scene)
                                     (Some (environment-of (parameter (page-address) "env")))
                                     format))
                        (match (● chosen second)
                          ((Some text)
                           (match (eye-of text)
                             ((Some eye) (placed over eye))
                             ((None) over)))
                          ((None) over))
                        (new Pair (first 0) (second 0))
                        format)))
          ((None)
           (write-line "no model: drop a .glb, a .gltf with its files, or an .hdr")
           (view-loop (None)
                      (fly-over (list -1.0 -1.0 -1.0) (list 1.0 1.0 1.0))
                      (new Pair (first 0) (second 0))
                      format))))))))

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
(define (model-scene (name String)) (→ Scene) (! gpu output-port resource tasks)
  (let ((files (sample-model name)))
    (match files
      ((Nil) (panic (string-append "no sample model " name)))
      ((Cons entry _)
       (loaded-scene (lambda ((paths (List String))) (→ (List Bytes)) (! resource tasks)
                       (read-resources (map (lambda (path) (model-file name files path)) paths)))
                     (● entry first))))))

(define (model-file (name String) (files (List (Pair String Resource))) (path String)) (→ Resource)
  (match (assoc-ref files path)
    ((Some file) file)
    ((None) (panic (string-append name (string-append " has no file " path))))))

;; The sample environment `env=` names, or the drawn sky.
(define (environment-of (name (Option String))) (→ Environment) (! gpu resource tasks)
  (match name
    ((Some "sky") (sky-environment sky 4096))
    ((Some name)
     (match (sample-environment name)
       ((Some file)
        (match (hdr-environment (read-resource file) 4096)
          ((Ok environment) environment)
          ((Err why) (panic (string-append name (string-append ": " why))))))
       ((None) (panic (string-append "no sample environment " name)))))
    ((None) (sky-environment sky 4096))))
