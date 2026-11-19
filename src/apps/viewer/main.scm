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
 (only (snail shell task) tasks)
 (only (snail shell app) next-event FrameEvent InputEvent FilesEvent KeyDown)
 (only (snail shell page) events report-ready)
 (only (snail shell fetch) fetch fetch-all-bytes page-address)
 (only (snail shell dom) dom document-root set-text)
 (only (snail shell dom page) with-page-dom)
 (snail shell files)
 (snail shell files page)
 (snail shell fetch page)
 (only (snail shell gpu) gpu request-device current-texture view-of work-done TextureFormat)
 (snail shell graphics pod)
 (snail shell graphics raster)
 (only (snail shell graphics gltf) uri-path reading unreadable attempt-reading)
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
    ((FilesEvent _) (opened view fly timing format (chosen-files) (None)))
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

;; ---- The files chosen ----

;; The view of the files chosen, the fly looking at a new scene from
;; `eye` or else from outside; or the view as it was, and why, when they
;; cannot be shown. The loop waits here, so one choice is read at a time,
;; and one that arrives meanwhile is read next.
(define (opened (view (Option View))
                (fly Fly)
                (timing (Pair I32 I32))
                (format TextureFormat)
                (files (List Chosen))
                (eye (Option (List F64))))
  (→ Unit)
  (! events gpu output-port tasks fetch files dom)
  (set-text (document-root) "Loading…")
  (match (attempt-reading (lambda () (chosen view files)))
    ((Ok replacing)
     (set-text (document-root) "")
     (view-loop (Some (shown view (● replacing first) (● replacing second) format))
                (match (● replacing first)
                  ((Some scene)
                   (let ((over (Fly-stops-set (fly-over (● scene low) (● scene high))
                                              (● fly stops))))
                     (match eye
                       ((Some eye) (fly-at over eye))
                       ((None) over))))
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
    (when (and (none? model) (or (none? light) (none? view)))
      (unreadable (string-append "nothing to show among " (show (length files)) " files")))
    (let* ((hdr (within light
                        (lambda (path) (radiance path (list-ref (read files path (list path)) 0)))))
           (scene (within model
                          (lambda (path)
                            (loaded-scene (lambda ((paths (List String)))
                                            (→ (List Bytes))
                                            (! fetch tasks reading)
                                            (read files path paths))
                                          path)))))
      (new Pair (first scene) (second (within hdr hdr-light))))))

;; The bytes of the paths that the file at `top` names, fetched together.
(define (read (files (List Chosen)) (top String) (paths (List String)))
  (→ (List Bytes))
  (! fetch tasks reading)
  (fetched (map (lambda (path) (address-of files top path)) paths)))

;; Where a path that the file at `top` names is fetched from: a file
;; chosen, at its address; or, when `top` is a link, the path itself,
;; since a scene at an address names its files relative to it. A scene
;; among the user's files reads nothing they did not choose.
(define (address-of (files (List Chosen)) (top String) (path String)) (→ String) (! reading)
  (match (find (lambda (file) (string=? (● file path) path)) files)
    ((Some file) (● file address))
    ((None)
     (if (any? (lambda (file) (and (string=? (● file path) top) (string=? (● file address) top)))
               files)
         path
         (unreadable (string-append path " is not among the files chosen"))))))

;; The bytes at each address, fetched together.
(define (fetched (addresses (List String))) (→ (List Bytes)) (! fetch tasks reading)
  (map (lambda (reply)
         (match reply
           ((Ok bytes) bytes)
           ((Err why) (unreadable why))))
       (fetch-all-bytes addresses)))

(define (none? (option (Option A))) (→ Bool) (∀ (A))
  (match option
    ((Some _) #f)
    ((None) #t)))

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
         (let ((format (● (request-device) format))
               (fly (fly-over (list -1.0 -1.0 -1.0) (list 1.0 1.0 1.0)))
               (timing (new Pair (first 0) (second 0)))
               (address (page-address)))
           (match (query-files address)
             ((Nil) (view-loop (None) fly timing format))
             (files (opened (None) fly timing format files (query-eye address)))))))))))
