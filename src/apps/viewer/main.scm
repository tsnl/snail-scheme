;; Fly through a glTF or GLB with the forward renderer. Drop files or URLs,
;; or open a file with O and a folder with Shift+O. An optional Radiance
;; panorama supplies the environment. The same inputs can be specified with
;; ?model=ADDRESS&env=ADDRESS&eye=x,y,z,yaw,pitch.
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
 (only (snail shell fetch) Fetch)
 (only (snail shell dom) Dom)
 (snail shell files)
 (only (snail shell gpu) Gpu view-of ViewObject TextureFormat)
 (snail shell graphics pod)
 (snail shell graphics raster)
 (only (snail shell graphics gltf) uri-path unreadable attempt-reading)
 (snail shell graphics forward scene)
 (only (snail shell graphics environment) Hdr read-hdr)
 (snail shell graphics forward environment)
 (snail shell graphics compositor)
 (snail shell graphics scene)
 (snail shell base64)
 (snail shell wire)
 (snail shell graphics forward render)
 (only (snail shell graphics passes) Filmic)
 (snail shell graphics fly))


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

(record Settings
  ((samples I64)))
(define first-settings (→ Settings) (new Settings (samples 1)))
(define (adjusted (input Input)) (→ (Option Settings))
  (match input
    ((KeyDown 49 _) (Some (new Settings (samples 1))))
    ((KeyDown 52 _) (Some (new Settings (samples 4))))
    (_ (None))))
(define (described (settings Settings)) (→ String)
  (string-append (show (● settings samples)) "× MSAA"))
(define (saved (settings Settings)) (→ Bytes)
  (list->array (list (i32->u8 (i64->i32 (● settings samples))))))
(define (restored (bytes Bytes)) (→ Settings)
  ;; The old two-byte save held a path count and resolution scale.
  (unless (or (= (array-length bytes) 1) (= (array-length bytes) 2))
    (panic "the viewer's save holds no settings"))
  (new Settings (samples (if (= (u8->i32 (array-ref bytes 0)) 4) 4 1))))

;; ---- The view ----

;; The scene shown, the light it is shown in, and the renderer drawing it.
(record View
  ((scene Scene)
   (environment Environment)
   (renderer Forward)
   (description SceneDescription)
   (recording (Option (List SceneFrame)))))

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
                   (compositor Compositor)
                   (save (Fn Settings → Unit))
                   (view (Option View))
                   (fly Fly)
                   (settings Settings))
  (→ Unit)
  (let loop ((view view) (fly fly) (settings settings) (timing (new Pair (first 0) (second 0))))
    (match (next-event events)
      ((FrameEvent elapsed)
       (match view
         ((Some shown)
          ;; The last frame's work finishes before this one's is queued, so
          ;; at most one frame waits on the device, and the device starts this
          ;; frame as soon as the last is done rather than at the next display
          ;; refresh after it.
          ((● gpu work-done))
          (let* ((fly (flown fly elapsed))
                 (_ (drawn gpu compositor shown fly settings)))
            ((● events report-ready))
            (loop (Some shown) fly settings (timed out timing elapsed))))
         ((None)
          ((● events report-ready))
          (loop view fly settings timing))))
      ((InputEvent (KeyDown 111 shift))
       ((● picker open-picker) (if shift (Folder) (SomeFiles)))
       (loop view fly settings timing))
      ((InputEvent (KeyDown 116 _))
       (match view ((Some shown) (toggle-recording! dom out shown)) (_ (unit)))
       (loop view fly settings timing))
      ((InputEvent (KeyDown 118 _))
       (match view ((Some current)
                    (let* ((r (● current renderer)) (next (- (remainder (+ (● r inspect) 2) 4) 1)))
                      (set! (● r inspect) next)
                      (say dom
                           out
                           (if (< next 0)
                               (described settings)
                               (string-append "Shadow cascade " (show (+ next 1)) " / 3")))))
              (_ (unit)))
       (loop view fly settings timing))
      ((InputEvent input)
       (match (adjusted input)
         ((Some changed)
          (say dom out (described changed))
          (loop view fly changed timing))
         ((None) (loop view (steered fly input) settings timing))))
      ((FilesEvent _)
       (match (opened gpu
                      dom
                      fetch
                      out
                      compositor
                      settings
                      view
                      fly
                      ((● picker chosen-files))
                      (None))
         ((Pair view fly) (loop view fly settings timing))))
      ((Hidden) (save settings) (loop view fly settings timing))
      ((SaveRequested) (save settings) (loop view fly settings timing))
      (_ (loop view fly settings timing)))))

(define (drawn (gpu Gpu) (compositor Compositor) (view View) (fly Fly) (settings Settings)) (→ Unit)
  (let* ((surface ((● gpu current-texture))) (w (● surface width)) (h (● surface height))
         (frame (scene-frame (fly-camera fly (/ (i32->f64 w) (i32->f64 h))) w h
                             (i64->i32 (● settings samples)) (fly-exposure fly))))
    (set! (● frame cascade) (● view renderer inspect))
    (present-scene! gpu (● view renderer) frame compositor surface)
    (match (● view recording)
      ((Some frames) (set! (● view recording) (Some (Cons frame frames))))
      ((None) (unit)))))

(define (stop-recording! (dom Dom) (out OutputPort) (view View) (frames (List SceneFrame))) (→ Unit)
  (set! (● view recording) (None))
  (if (null? frames) (say dom out "No frames recorded.")
      (let* ((clip (new SceneRecording (scene (● view description)) (frames (reverse frames))))
             (link ((● dom create-element) "a")) (root ((● dom document-root))))
        (say dom out (string-append (show (length frames)) " frames recorded. "))
        ((● dom set-text) link "Download scene recording")
        ((● dom set-attribute) link "download" "view.snail-scene")
        ((● dom set-attribute) link "href" (data-url "application/octet-stream" (serialize clip)))
        ((● dom insert-node) root link (None)))))

(define (toggle-recording! (dom Dom) (out OutputPort) (view View)) (→ Unit)
  (match (● view recording)
    ((Some frames) (stop-recording! dom out view frames))
    ((None) (set! (● view recording) (Some (Nil))) (say dom out "Recording. Press T to finish."))))

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
                (compositor Compositor)
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
     (match view
       ((Some v)
        (match (● v recording) ((Some frames) (stop-recording! dom out v frames)) (_ (unit))))
       (_ (unit)))
     (new Pair
       (first (Some (shown gpu view (● replacing first) (● replacing second) settings
                           (new SceneDescription
                             (model (match (outermost (ending files (list ".glb" ".gltf")))
                                      ((Some path) path)
                                      ((None)
                                       (match view ((Some v) (● v description model)) (_ "")))))
                             (sky (match (outermost (ending files (list ".hdr")))
                                    ((Some path) (Panorama path))
                                    ((None)
                                     (match view
                                       ((Some v) (● v description sky))
                                       (_ (BakedSky 1))))))
                             (tone (Filmic))))))
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

(define (hdr-light (gpu Gpu) (hdr Hdr)) (→ Environment) (import-hdr gpu hdr))

(define (shown (gpu Gpu) (view (Option View)) (scene (Option Scene)) (light (Option Environment))
               (settings Settings) (description SceneDescription)) (→ View)
               (let* ((model
                       (match scene ((Some s) s) ((None) (match view ((Some old) (● old scene))
                                                                ((None)
                                                                 (panic
                                                                  "a first view needs a scene"))))))
                      (env (match light
                             ((Some e) e)
                             ((None) (match view ((Some old) (● old environment))
                                            ((None) (daylight gpu 1))))))
                      (canvas ((● gpu current-texture)))
                      (renderer (make-forward gpu model env (● canvas width)
                                              (● canvas height)
                                              (i64->i32 (● settings samples))
                                              (Filmic))))
                 (match view
                   ((Some old) (release-forward gpu (● old renderer))
                    (match scene ((Some _) (release-scene gpu (● old scene))) (_ (unit)))
                    (match light
                      ((Some _) (release-environment gpu (● old environment)))
                      (_ (unit))))
                   (_ (unit)))
                 (new View
                   (scene model)
                   (environment env)
                   (renderer renderer)
                   (description description)
                   (recording (None)))))

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
  (let ((scene (load-scene gpu read path)))
    (write-line out (string-append "scene: "
                                   (show (● scene vertex-count))
                                   " vertices, "
                                   (show
                                    (quotient (fold-left (lambda (n d) (+ n (i32->i64 (● d count))))
                                                         0
                                                         (● scene draws))
                                              3))
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
  (let* ((compositor (make-compositor gpu (● ((● gpu request-device)) format)))
         (outside (fly-over (list -1.0 -1.0 -1.0) (list 1.0 1.0 1.0)))
         (address ((● fetch page-address))))
    (match (match (query-files address)
             ((Nil) (new Pair (first (None)) (second outside)))
             (files
              (opened gpu
                      dom
                      fetch
                      out
                      compositor
                      settings
                      (None)
                      outside
                      files
                      (query-eye address))))
      ((Pair view fly)
       (view-loop gpu dom picker events fetch out compositor save view fly settings)))))
