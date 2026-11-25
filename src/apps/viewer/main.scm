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
;; places the camera. Still frames trace a checkerboard by default, and
;; &spp=1 traces every pixel. Without an eye, the camera looks at the
;; scene from outside. Files that cannot be shown leave the view as it
;; was, and the page says why. The frames average while the camera holds
;; still. Keys 1 to 8 set the bounce count, and - and = set the resolution.
;; The page keeps these settings for the next visit.
(import
 (snail core base)
 (snail core io)
 (snail shell json)
 (snail shell json read)
 (only (snail shell app)
       next-event
       FrameEvent
       InputEvent
       FilesEvent
       Input
       KeyDown
       Hidden
       SaveRequested)
 (only (snail shell page) Events PageStorage run-page)
 (only (snail shell math) exp)
 (only (snail shell fetch) Fetch)
 (only (snail shell dom) Dom)
 (snail shell files)
 (only (snail shell gpu) Gpu view-of TextureFormat)
 (snail shell graphics pod)
 (snail shell graphics raster)
 (only (snail shell graphics gltf) uri-path unreadable attempt-reading)
 (snail shell graphics trace scene)
 (snail shell graphics environment)
 (snail shell graphics trace render)
 (snail shell graphics fly))

(define layer-size (→ I32) 1024)

(define (parameter (address String) (name String)) (→ (Option String))
  (let ((page (match (string-index address #\#)
                ((Some end) (substring address 0 end))
                ((None) address))))
    (match (string-index page #\?)
      ((Some at)
       (query-field (substring page (+ at 1) (string-length page)) (string-append name "=")))
      ((None) (None)))))

;; Match a whole query field before decoding its value so an escaped
;; ampersand in a model URL stays part of that URL.
(define (query-field (query String) (key String)) (→ (Option String))
  (let* ((size (string-length query)) (n (string-length key))
         (end (match (string-index query #\&) ((Some at) at) ((None) size))))
    (cond ((and (<= n end) (string=? (substring query 0 n) key))
           (Some (uri-path (substring query n end))))
          ((< end size) (query-field (substring query (+ end 1) size) key))
          (else (None)))))

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

;; ---- Settings ----

;; What a frame costs: how many times its paths bounce, and how many
;; times the pixels it traces are halved from the canvas's, each side
;; shrinking by the square root of two, for Post to scale up to the
;; canvas. The page's save holds them.
(record Settings
  ((bounces I64)
   (halvings I64)))

(define first-settings (→ Settings) (new Settings (bounces 4) (halvings 0)))

;; An eighth of each side at most.
(define most-halvings (→ I64) 6)

;; The settings a key changes: 1 to 8 the bounces, - halves the pixels
;; and = (or +) doubles them; none for any other input.
(define (adjusted (settings Settings) (input Input)) (→ (Option Settings))
  (match input
    ((KeyDown key _)
     (cond ((and (>= key 49) (<= (i32->i64 key) (+ 48 most-bounces)))
            (Some (Settings-bounces-set settings (i32->i64 (- key 48)))))
           ((= key 45) (Some (halved settings 1)))
           ((or (= key 61) (= key 43)) (Some (halved settings -1)))
           (else (None))))
    (_ (None))))

(define (halved (settings Settings) (more I64)) (→ Settings)
  (Settings-halvings-set settings (max 0 (min most-halvings (+ (● settings halvings) more)))))

;; The share of each side of the canvas traced: two to the power of
;; minus half the halvings.
(define (side-scale (settings Settings)) (→ F64)
  (exp (* -0.5 (* 0.6931471805599453 (i64->f64 (● settings halvings))))))

;; A side of the canvas, `side` pixels long, as traced: at least a pixel.
(define (traced (settings Settings) (side I32)) (→ I32)
  (max 1 (f64->i32 (round (* (side-scale settings) (i32->f64 side))))))

(define (described (settings Settings)) (→ String)
  (string-append (show (● settings bounces))
                 (if (= (● settings bounces) 1) " bounce" " bounces")
                 " at "
                 (show (f64->i64 (round (* 100.0 (side-scale settings)))))
                 "% resolution"))

;; The settings as the page saves them, a byte each, and back; bytes
;; that are not settings trap, and the page starts again without them.
(define (saved (settings Settings)) (→ Bytes)
  (array-generate 2
                  (lambda (index)
                    (i32->u8 (i64->i32 (if (= index 0)
                                           (● settings bounces)
                                           (● settings halvings)))))))

(define (restored (bytes Bytes)) (→ Settings)
  (unless (= (array-length bytes) 2) (panic "the viewer's save holds no settings"))
  (let ((bounces (i32->i64 (u8->i32 (array-ref bytes 0))))
        (halvings (i32->i64 (u8->i32 (array-ref bytes 1)))))
    (unless (and (>= bounces 1) (<= bounces most-bounces) (<= halvings most-halvings))
      (panic "the viewer's save holds no settings"))
    (new Settings (bounces bounces) (halvings halvings))))

;; ---- The view ----

;; The scene shown, the light it is shown in, and the tracer drawing it.
(record View
  ((scene Scene)
   (environment Environment)
   (tracer Tracer)))

;; The page's events, each answered with the next view. The view, the
;; fly, the settings and the frame count are what change from one event
;; to the next; what the loop reaches the page through, and how it saves
;; the settings, it is handed once.
(define (view-loop (gpu Gpu)
                   (dom Dom)
                   (picker FilePicker)
                   (events Events)
                   (fetch Fetch)
                   (out OutputPort)
                   (format TextureFormat)
                   (save (Fn Settings → Unit))
                   (sampling TraceSampling)
                   (view (Option View))
                   (fly Fly)
                   (settings Settings))
  (→ Unit)
  (let loop ((view view) (fly fly) (settings settings) (timing (new Pair (first 0) (second 0))))
    (match (next-event events)
      ((FrameEvent elapsed)
       (match view
         ((Some shown)
          (let* ((fly (flown fly elapsed))
                 (shown (View-tracer-set shown (drawn gpu (● shown tracer) fly settings sampling))))
            ((● gpu work-done))
            ((● events report-ready))
            (loop (Some shown) fly settings (timed out timing elapsed))))
         ((None)
          ((● events report-ready))
          (loop view fly settings timing))))
      ((InputEvent (KeyDown 111 shift))
       ((● picker open-picker) (if shift (Folder) (SomeFiles)))
       (loop view fly settings timing))
      ((InputEvent input)
       (match (adjusted settings input)
         ((Some changed)
          (say dom out (described changed))
          (loop view fly changed timing))
         ((None) (loop view (steered fly input) settings timing))))
      ((FilesEvent _)
       (match (opened gpu dom fetch out format settings view fly ((● picker chosen-files)) (None))
         ((Pair view fly) (loop view fly settings timing))))
      ((Hidden) (save settings) (loop view fly settings timing))
      ((SaveRequested) (save settings) (loop view fly settings timing))
      (_ (loop view fly settings timing)))))

;; A frame drawn into the canvas, from where the fly is, traced at the
;; size and with the bounces the settings ask for.
(define (drawn (gpu Gpu) (tracer Tracer) (fly Fly) (settings Settings) (sampling TraceSampling))
  (→ Tracer)
  (let* ((canvas ((● gpu current-texture)))
         (height (traced settings (● canvas height))))
    (draw-sampled-traced gpu (resize-tracer gpu tracer (traced settings (● canvas width)) height)
                         (view-of gpu (● canvas texture) 1)
                         (fly-camera fly
                                     (/ (i32->f64 (● canvas width))
                                        (i32->f64 (max 1 (● canvas height)))))
                         (fly-spread height)
                         (fly-exposure fly)
                         (● settings bounces) #f sampling)))

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
;; and one that arrives meanwhile is read next. Shown, the page says the
;; settings unless they are the first ones, which a visit may have saved.
(define (opened (gpu Gpu)
                (dom Dom)
                (fetch Fetch)
                (out OutputPort)
                (format TextureFormat)
                (settings Settings)
                (view (Option View))
                (fly Fly)
                (files (List Chosen))
                (eye (Option (List F64))))
  (→ (Pair (Option View) Fly))
  ((● dom set-text) ((● dom document-root)) "Loading…")
  (match (attempt-reading (lambda () (chosen gpu fetch out view files)))
    ((Ok replacing)
     ((● dom set-text) ((● dom document-root))
      (if (string=? (described settings) (described first-settings))
          ""
          (described settings)))
     (new Pair
       (first (Some (shown gpu view (● replacing first) (● replacing second) format settings)))
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
  ((● dom set-text) ((● dom document-root)) message)
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
       ((● fetch fetch-all-bytes) addresses)))

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
;; first view needs a scene, and without a light has the drawn sky's; its
;; tracer is made at the size the settings trace.
(define (shown (gpu Gpu) (view (Option View))
               (scene (Option Scene))
               (light (Option Environment))
               (format TextureFormat)
               (settings Settings))
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
     (let ((canvas ((● gpu current-texture)))
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
                       (traced settings (● canvas width))
                       (traced settings (● canvas height))
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
              (storage PageStorage)
              (out OutputPort))
  (→ Unit)
  (run-page events
            storage
            (lambda () first-settings)
            saved
            restored
            (lambda ((settings Settings) (save (Fn Settings → Unit)))
              (→ Unit)
              (viewed gpu dom fetch picker events out settings save))))

;; The page from its query's files, or from nothing, with the settings it
;; saved.
(define (viewed (gpu Gpu)
                (dom Dom)
                (fetch Fetch)
                (picker FilePicker)
                (events Events)
                (out OutputPort)
                (settings Settings)
                (save (Fn Settings → Unit)))
  (→ Unit)
  (let* ((format (● ((● gpu request-device)) format))
         (outside (fly-over (list -1.0 -1.0 -1.0) (list 1.0 1.0 1.0)))
         (address ((● fetch page-address)))
         (sampling (match (parameter address "spp") ((Some "1") (EveryPixel)) (_ (Checkerboard)))))
    (match (match (query-files address)
             ((Nil) (new Pair (first (None)) (second outside)))
             (files
              (opened gpu dom fetch out format settings (None) outside files (query-eye address))))
      ((Pair view fly)
       (view-loop gpu dom picker events fetch out format save sampling view fly settings)))))
