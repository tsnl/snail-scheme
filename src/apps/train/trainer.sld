;; Training 3D Gaussian Splatting on a COLMAP scene, as the reference
;; trains (Kerbl et al., 2023): the sparse points start the cloud, and
;; each step renders one photograph's view, descends the loss, and every
;; 100 steps from 500 to 15,000 densifies. Every eighth photograph, in
;; order of name, is held out, and the PSNR on those is reported at the
;; end. A photograph is on the device only around the step that trains on
;; it, so a scene's photographs need not fit there together.
;;
;; The trainer runs wherever its two needs are met. `dataset` is where the
;; scene's files come from: a page fetches them from the scene's URL
;; (main.scm), and a program on Node reads them from its folder
;; (node.scm). `train` is given how a step's image is shown: on the
;; page's canvas, each 50th step, or nowhere.
;;
;; The settings are `name=value` pairs, a page's query or a program's
;; arguments: the scene's address (`scene`, by default /datasets/bicycle/),
;; the folder of photographs within it (`images`, by default `images_4`,
;; a quarter as wide as the originals, at which the paper trains Mip-NeRF
;; 360's outdoor scenes), the steps (`steps`, 30,000) and the most
;; gaussians the device holds (`gaussians`, 4,194,304).
(define-library (apps train trainer)
  (export
   train
   settings-of
   dataset
   dataset-bytes
   shown-on-canvas
   shown-nowhere)
  (import
   (snail core base)
   (snail core io)
   (only (snail core forms) host)
   (only (snail shell task) tasks dispatch Mailbox make-mailbox mailbox-post mailbox-receive)
   (snail shell gpu)
   (only (snail shell math) log)
   (only (snail shell random) Random make-random random-next random-below)
   (only (snail shell tensor) View Float Unsigned param scalar minimum mean square)
   (only (snail shell tensor eval) values->bytes bytes->values)
   (snail shell tensor compile)
   (snail shell graphics pod)
   (snail shell graphics colmap)
   (snail shell graphics splat-train)
   (snail shell graphics splat-fit)
   (apps train shaders))
  (begin

    ;; ---- Settings ----

    (record Settings
      ((scene String)
       (images String)
       (steps I64)
       (gaussians I64)
       (profile Bool)))

    ;; The settings in a page address's query, `name=value` pairs after
    ;; its `?`, each one missing at its default.
    (define (settings-of (address String)) (→ Settings)
      (let* ((query (match (string-index address #\?)
                      ((Some at) (substring address (+ at 1) (string-length address)))
                      ((None) "")))
             (pairs (map (lambda (part) (split-on part #\=)) (split-on query #\&)))
             (value (lambda (name default)
                      (match (find (lambda (pair)
                                     (and (= (length pair) 2) (string=? (list-ref pair 0) name)))
                                   pairs)
                        ((Some pair) (list-ref pair 1))
                        ((None) default)))))
        (new Settings
          (scene (value "scene" "/datasets/bicycle/"))
          (images (value "images" "images_4"))
          (steps (number (value "steps" "30000") 30000))
          (gaussians (number (value "gaussians" "4194304") 4194304))
          (profile (string=? (value "profile" "0") "1")))))

    (define (number (text String) (default I64)) (→ I64)
      (match (string->i64 text)
        ((Some n) n)
        ((None) default)))

    ;; The pieces of a text between each `separator`.
    (define (split-on (text String) (separator Char)) (→ (List String))
      (match (string-index text separator)
        ((Some at)
         (Cons (substring text 0 at)
               (split-on (substring text (+ at 1) (string-length text)) separator)))
        ((None) (list text))))

    ;; ---- Scenes ----

    ;; The camera, the address of the photographs' folder, their size and
    ;; how much they are scaled from the camera, the poses to train on
    ;; and those held out, the sparse points, and the extent of the
    ;; cameras, which sizes the thresholds.
    (record Scene
      ((camera ColmapCamera)
       (photographs String)
       (width I64)
       (height I64)
       (scale F64)
       (training (List ColmapImage))
       (held (List ColmapImage))
       (points (List ColmapPoint))
       (extent F64)))

    ;; Where the scene's files come from: the bytes at an address, which
    ;; begins with the scene's.
    (effect dataset
      ((dataset-bytes (Fn String → Bytes ! tasks))))

    (define (parsed (result (Result T String))) (→ T) (∀ (T))
      (match result
        ((Ok value) value)
        ((Err why) (panic why))))

    (define (load-scene (settings Settings)) (→ Scene) (! dataset gpu tasks)
      (let* ((base (● settings scene))
             (camera (list-ref
                      (parsed
                       (read-cameras (dataset-bytes (string-append base "sparse/0/cameras.bin"))))
                      0))
             (images (list-sort (lambda (a b) (string<? (● a name) (● b name)))
                                (parsed (read-images
                                         (dataset-bytes
                                          (string-append base "sparse/0/images.bin"))))))
             (points
              (parsed (read-points (dataset-bytes (string-append base "sparse/0/points3D.bin")))))
             (photographs (string-append base (● settings images) "/"))
             (first (photograph photographs (list-ref images 0))))
        (destroy (TextureObject (● first texture)))
        (new Scene
          (camera camera)
          (photographs photographs)
          (width (i32->i64 (● first width)))
          (height (i32->i64 (● first height)))
          (scale (/ (i32->f64 (● first width)) (i64->f64 (● camera width))))
          (training (filter-indexed (lambda (k) (not (= (remainder k 8) 0))) images))
          (held (filter-indexed (lambda (k) (= (remainder k 8) 0)) images))
          (points points)
          (extent (extent-of images)))))

    (define (filter-indexed (keep (Fn I64 → Bool)) (items (List T))) (→ (List T)) (∀ (T))
      (map (lambda (pair) (● pair second))
           (filter (lambda (pair) (keep (● pair first))) (zip (iota (length items)) items))))

    ;; 1.1 times the largest distance of a camera's center, -R^T t, from
    ;; their mean, as the reference measures a scene.
    (define (extent-of (images (List ColmapImage))) (→ F64)
      (let* ((centers (map image-center images))
             (count (i64->f64 (length centers)))
             (mean (map (lambda (k)
                          (/ (fold-left + 0.0 (map (lambda (c) (list-ref c k)) centers)) count))
                        (iota 3)))
             (distance (lambda (c)
                         (sqrt (fold-left +
                                          0.0
                                          (map (lambda (k)
                                                 (let ((d (- (list-ref c k) (list-ref mean k))))
                                                   (* d d)))
                                               (iota 3)))))))
        (* 1.1 (fold-left max 0.0 (map distance centers)))))

    ;; ---- Photographs ----

    ;; A scene's photographs do not fit the device together at full size:
    ;; bicycle's 194 take 12.6 GB as textures. So each is read and
    ;; decoded for the step that trains on it and let go after it. One
    ;; takes longer to decode than a step takes, so the photographs of the
    ;; next `ahead` steps are on their way at once, each in a task of its
    ;; own, and the device holds that many and the step's.
    (define ahead (→ I64) 4)

    (define (photograph (folder String) (image ColmapImage)) (→ Image) (! dataset gpu tasks)
      (let ((url (string-append folder (● image name))))
        (match (decode-image (dataset-bytes url))
          ((Some photo) photo)
          ((None) (panic (string-append url " is no image the host decodes"))))))

    ;; A photograph on its way: its pose, and where its task posts it.
    (record Arriving
      ((image ColmapImage)
       (photo (Mailbox Image))))

    (define (sent-for (scene Scene) (image ColmapImage))
      (→ Arriving)
      (! dataset gpu tasks mut host)
      (let ((arriving (new Arriving (image image) (photo (make-mailbox)))))
        (dispatch
         (lambda ()
           (mailbox-post (● arriving photo) (photograph (● scene photographs) image))))
        arriving))

    ;; ---- Programs ----

    ;; The three programs for a capacity of gaussians and of the entries
    ;; they are binned into, on one set of params, the step's;
    ;; densification's also counts the live.
    (record Programs
      ((capacity I64)
       (sensor Sensor)
       (step Program)
       (densify Program)
       (reset Program)))

    (define (sensor-of (scene Scene) (entries I64)) (→ Sensor)
      (new Sensor (width (● scene width)) (height (● scene height)) (capacity entries)))

    (define (programs-for (scene Scene) (capacity I64) (entries I64)) (→ Programs) (! gpu)
      (let* ((cloud (splat-params capacity))
             (sensor (sensor-of scene entries))
             (training (training-step cloud sensor))
             (step (compile-program "step" (● training first) (● training second)))
             (densified (densification cloud (stats-params capacity))))
        (new Programs
          (capacity capacity)
          (sensor sensor)
          (step step)
          (densify
           (compile-program-sharing "densify" (list (● densified second)) (● densified first) step))
          (reset (compile-program-sharing "reset" (Nil) (opacity-reset cloud) step)))))

    (define (release-programs (p Programs)) (→ Unit) (! gpu)
      (release-program (● p reset))
      (release-program (● p densify))
      (release-program (● p step)))

    (define (floats (values (List F64))) (→ Bytes) (values->bytes (list->array values) (Float)))

    (define (rows (count I64) (capacity I64) (width I64) (row (Fn I64 → (List F64)))) (→ Bytes)
      (floats
       (concatenate (map (lambda (i) (if (< i count) (row i) (map (lambda (_) 0.0) (iota width))))
                         (iota capacity)))))

    ;; ---- Starting ----

    ;; The sparse points as gaussians: each at its point, its color its
    ;; point's, its scale the root of the mean squared distance to its
    ;; three nearest neighbours, unrotated, with opacity 0.1, and only
    ;; degree 0 shading, as the reference starts.
    (define (start-cloud (p Programs) (scene Scene)) (→ Unit) (! gpu tasks)
      (let* ((points (list->array (● scene points)))
             (count (array-length points))
             (capacity (● p capacity))
             (step (● p step))
             (scales (initial-scales points))
             (position (lambda (i) (● (array-ref points i) position))))
        (write-param step "means" (rows count capacity 3 position))
        (write-param step
                     "scales"
                     (rows count
                           capacity
                           3
                           (lambda (i) (let ((s (array-ref scales i))) (list s s s)))))
        (write-param step "rotations" (rows count capacity 4 (lambda (i) (list 0.0 0.0 0.0 1.0))))
        (write-param step "opacities" (rows count capacity 1 (lambda (i) (list (log (/ 0.1 0.9))))))
        (write-param step
                     "dc"
                     (rows count
                           capacity
                           3
                           (lambda (i)
                             (map (lambda (c) (/ (- c 0.5) 0.28209479177387814))
                                  (● (array-ref points i) color)))))
        (write-param step "live" (rows count capacity 1 (lambda (i) (list 1.0))))
        (write-param step "degrees" (floats (list 0.0 0.0 0.0)))
        (write-param (● p densify) "extent" (floats (list (● scene extent))))))

    ;; log(sqrt(d)) of each point's mean squared distance to its three
    ;; nearest, at least 1e-7.
    (define (initial-scales (points (Array ColmapPoint))) (→ (Array F64)) (! gpu tasks)
      (let* ((count (array-length points))
             (view (param "points" (list count 3) (Float)))
             (program (compile-program "nearest" (list (nearest-distances view)) (Nil))))
        (write-param program
                     "points"
                     (rows count count 3 (lambda (i) (● (array-ref points i) position))))
        (run-program program)
        (let ((distances (bytes->values (read-sink program 0) (Float))))
          (release-program program)
          (list->array
           (map (lambda (i) (log (sqrt (max (array-ref distances i) 0.0000001)))) (iota count))))))

    ;; ---- Stepping ----

    ;; One step on a photograph: its texels copied into the target, its
    ;; camera and the centers' rate written, then the step's program.
    (define (step-on (p Programs) (scene Scene) (image ColmapImage) (photo Image) (rate F64))
      (→ Unit)
      (! gpu)
      (aim (● p step) (● p sensor) scene image photo)
      (write-param (● p step) "rate" (floats (list rate)))
      (run-program (● p step)))

    ;; A program's target and camera set to a photograph and its pose. The
    ;; copy is submitted here, so the photograph may be let go after.
    (define (aim (program Program) (sensor Sensor) (scene Scene) (image ColmapImage) (photo Image))
      (→ Unit)
      (! gpu)
      (let ((encoder (create-command-encoder)))
        (copy-texture-to-buffer encoder
                                (whole-texture (● photo texture))
                                (param-buffer program "target")
                                0
                                (i64->i32 (* 4 (texel-pitch (● sensor width))))
                                (i64->i32 (● sensor width))
                                (i64->i32 (● sensor height)))
        (submit (list (finish encoder)))
        (write-param program
                     "camera"
                     (floats (camera-values (● scene camera) image (● scene scale))))))

    ;; The second step's twelve slowest dispatches, each run alone, with
    ;; the seconds it took and its kernel, and the step's twelve largest
    ;; kinds of buffer; the first step touches every buffer, which the
    ;; device clears then.
    (define (profile (p Programs) (scene Scene)) (→ Unit) (! clock dataset gpu output-port tasks)
      (let* ((image (list-ref (● scene training) 0))
             (photo (photograph (● scene photographs) image)))
        (step-on p scene image photo 0.0001)
        (destroy (TextureObject (● photo texture))))
      (work-done)
      (let ((times (list-sort (lambda (a b) (> (● a second) (● b second)))
                              (profile-program (● p step)))))
        (write-line (string-append (show (length times))
                                   " dispatches, "
                                   (f64->string
                                    (fold-left + 0.0 (map (lambda (t) (● t second)) times)))
                                   " seconds"))
        (for-each
         (lambda (t) (write-line (string-append (f64->string (● t second)) " " (● t first))))
         (take times 12))
        (for-each
         (lambda (m) (write-line (string-append (show (● m second)) " bytes: " (● m first))))
         (take (program-memory (● p step)) 12))
        (write-line (string-append (show (bytes-made (● p step)))
                                   " bytes made for the step, "
                                   (show (bytes-made (● p densify)))
                                   " for densifying"))))

    (define (bytes-made (program Program)) (→ I64)
      (fold-left + 0 (map (lambda (m) (● m second)) (program-memory program))))

    (define (scalar-of (bytes Bytes)) (→ F64) (array-ref (bytes->values bytes (Float)) 0))

    ;; Densifying, then programs for twice the capacity once more than
    ;; half of it is live, up to `most` gaussians, with at least eight
    ;; entries a gaussian. A full cloud densifies only as far as its room.
    (define (densified (p Programs) (scene Scene) (step I64) (most I64))
      (→ (Pair Programs I64))
      (! gpu tasks)
      (write-param (● p densify) "prune-big" (floats (list (if (> step 3000) 1.0 0.0))))
      (write-param (● p densify)
                   "seed"
                   (values->bytes
                    (list->array (list (i64->f64 (remainder (* step 2654435761) 4294967296))))
                    (Unsigned)))
      (run-program (● p densify))
      (let ((live (f64->i64 (scalar-of (read-sink (● p densify) 0)))))
        (if (and (> (* 2 live) (● p capacity)) (< (● p capacity) most))
            (new Pair
              (first (let ((capacity (min most (* 2 (● p capacity)))))
                       (grown p scene capacity (max (● p sensor capacity) (* 8 capacity)))))
              (second live))
            (new Pair (first p) (second live)))))

    ;; Programs twice as roomy for entries once the last step's binning
    ;; asked for more than three quarters of them, up to 2^27.
    (define (roomy (p Programs) (scene Scene)) (→ Programs) (! gpu tasks)
      (let ((entries (scalar-of (read-sink (● p step) 2))) (room (● p sensor capacity)))
        (if (and (> (* 4.0 entries) (* 3.0 (i64->f64 room))) (< room 134217728))
            (grown p scene (● p capacity) (* 2 room))
            p)))

    ;; Larger programs on the same params: stashed, the old programs
    ;; released, and given back, so only one set of scratch is ever held.
    ;; Densification's own params are written as it runs, but the extent.
    (define (grown (p Programs) (scene Scene) (capacity I64) (entries I64)) (→ Programs) (! gpu)
      (let ((stash (stash-params (● p step))))
        (release-programs p)
        (let ((bigger (programs-for scene capacity entries)))
          (unstash-params stash (● bigger step))
          (write-param (● bigger densify) "extent" (floats (list (● scene extent))))
          bigger)))

    ;; ---- Showing ----

    (record Presenter
      ((pipeline GpuRenderPipeline)
       (sizes GpuBuffer)))

    (define (make-presenter (format TextureFormat)) (→ Presenter) (! gpu)
      (new Presenter
        (pipeline (create-render-pipeline
                   (new RenderPipelineDescriptor
                     (label "present")
                     (module (create-shader-module
                              (new ShaderModuleDescriptor (label "present") (code present-shader))))
                     (vertex-entry "present_vertex")
                     (buffers (Nil))
                     (fragment (Some (new FragmentState
                                       (entry "present_fragment")
                                       (targets (list (Some (new ColorTarget
                                                              (format format)
                                                              (blend (None)))))))))
                     (topology (TriangleList))
                     (cull (CullNone))
                     (depth (None)))))
        (sizes (create-buffer (new BufferDescriptor
                                (label "present/sizes")
                                (size 16)
                                (usage (list (Uniform) (CopyDst))))))))

    ;; The step's image drawn into the canvas.
    ;; How a page shows a step: its image on the canvas, whose format is
    ;; `format`. And how a host without a screen does.
    (define (shown-on-canvas (format TextureFormat)) (→ (Fn Programs → Unit ! gpu)) (! gpu)
      (let ((presenter (make-presenter format)))
        (lambda ((p Programs)) (→ Unit) (! gpu) (present presenter p))))

    (define (shown-nowhere (p Programs)) (→ Unit) (unit))

    (define (present (presenter Presenter) (p Programs)) (→ Unit) (! gpu)
      (let* ((canvas (current-texture))
             (sensor (● p sensor))
             (group (create-bind-group (new BindGroupDescriptor
                                         (label "present")
                                         (pipeline (RenderPipeline (● presenter pipeline)))
                                         (group 0)
                                         (entries (list (BufferEntry 0 (● presenter sizes) 0 0)
                                                        (BufferEntry 1
                                                                     (sink-buffer (● p step) 1)
                                                                     0
                                                                     0))))))
             (encoder (create-command-encoder))
             (pass (begin-render-pass encoder
                                      (new RenderPassDescriptor
                                        (colors (list (Some (new ColorAttachment
                                                              (view (view-of (● canvas texture) 1))
                                                              (load (Clear (new Color
                                                                             (red 0.0)
                                                                             (green 0.0)
                                                                             (blue 0.0)
                                                                             (alpha 1.0))))
                                                              (store #t)))))
                                        (depth (None))))))
        (write-buffer (● presenter sizes) 0 (floats (list (i32->f64 (● canvas width))
                                                          (i32->f64 (● canvas height))
                                                          (i64->f64 (● sensor width))
                                                          (i64->f64 (● sensor height)))))
        (set-pipeline pass (● presenter pipeline))
        (set-bind-group pass 0 group)
        (draw pass 3 1 0 0)
        (end-pass pass)
        (submit (list (finish encoder)))
        (destroy (BindGroupObject group))))

    ;; ---- Training ----

    ;; Where training is: the programs, the photographs not yet sent for
    ;; this round, the generator that picks among them, those on their
    ;; way, in the order the steps train on them, the step, how many
    ;; gaussians are live, and when it started.
    (record Run
      ((programs Programs)
       (round (List ColmapImage))
       (random Random)
       (arriving (List Arriving))
       (step I64)
       (live I64)
       (started I64)))

    ;; Training by `settings`, on the device the host has opened, each
    ;; 50th step's image and the last shown by `shown`.
    (define (train (settings Settings) (shown (Fn Programs → Unit ! gpu)))
      (→ Unit)
      (! clock dataset gpu output-port tasks mut host)
      (let* ((scene (load-scene settings))
             (capacity (min (● settings gaussians) (max 1048576 (* 2 (length (● scene points))))))
             (p (programs-for scene capacity (* 4 capacity))))
        (start-cloud p scene)
        (when (● settings profile) (profile p scene))
        (write-line (string-append "training "
                                   (show (length (● scene training)))
                                   " photographs of "
                                   (show (● scene width))
                                   "x"
                                   (show (● scene height))
                                   " from "
                                   (show (length (● scene points)))
                                   " points"))
        (let ((done (trained (fold-left (lambda (run _) (sending run scene))
                                        (new Run
                                          (programs p)
                                          (round (Nil))
                                          (random (make-random 1))
                                          (arriving (Nil))
                                          (step 1)
                                          (live (length (● scene points)))
                                          (started (monotonic-nanoseconds)))
                                        (iota (min ahead (● settings steps))))
                             scene
                             settings
                             shown)))
          (shown (● done programs))
          (write-line (string-append "held-out PSNR "
                                     (f64->string (held-out-psnr (● done programs) scene)))))))

    ;; The run with one more photograph sent for: one not yet sent for
    ;; this round, picked at random, from a new round once every one has
    ;; been.
    (define (sending (run Run) (scene Scene)) (→ Run) (! dataset gpu tasks mut host)
      (let* ((round (if (null? (● run round)) (● scene training) (● run round)))
             (random (random-next (● run random)))
             (pick (random-below random (length round))))
        (Run-arriving-set (Run-random-set (Run-round-set run (without round pick)) random)
                          (append (● run arriving)
                                  (list (sent-for scene (list-ref round pick)))))))

    (define (without (items (List T)) (k I64)) (→ (List T)) (∀ (T))
      (append (take items k) (list-drop items (+ k 1))))

    (define (trained (run Run)
                     (scene Scene)
                     (settings Settings)
                     (shown (Fn Programs → Unit ! gpu)))
      (→ Run)
      (! clock dataset gpu output-port tasks mut host)
      (match (● run arriving)
        ((Cons next rest)
         (let ((sent (Run-arriving-set run rest)))
           (trained (stepped (if (<= (+ (● run step) ahead) (● settings steps))
                                 (sending sent scene)
                                 sent)
                             scene
                             settings
                             shown
                             next)
                    scene
                    settings
                    shown)))
        ((Nil) run)))

    ;; One step, on the photograph that has arrived for it, and what its
    ;; number asks for after it: densifying, an opacity reset, another
    ;; degree of harmonics, a wait, the canvas, a report.
    (define (stepped (run Run)
                     (scene Scene)
                     (settings Settings)
                     (shown (Fn Programs → Unit ! gpu))
                     (next Arriving))
      (→ Run)
      (! clock gpu output-port tasks mut)
      (let ((step (● run step)) (p (● run programs)) (photo (mailbox-receive (● next photo))))
        (step-on p
                 scene
                 (● next image)
                 photo
                 (rate-of-means step (● settings steps) (● scene extent)))
        (destroy (TextureObject (● photo texture)))
        (when (= (remainder step 1000) 0)
          (write-param (● p step)
                       "degrees"
                       (floats
                        (map (lambda (d) (if (<= d (quotient step 1000)) 1.0 0.0)) (list 1 2 3)))))
        (when (or (<= step 3) (= (remainder step 100) 0)) (report run p))
        (let* ((roomier (if (= (remainder step 100) 0) (roomy p scene) p))
               (densify? (and (>= step 500) (<= step 15000) (= (remainder step 100) 0)))
               (after (if densify?
                          (densified roomier scene step (● settings gaussians))
                          (new Pair (first roomier) (second (● run live))))))
          (when (and (= (remainder step 3000) 0) (<= step 15000))
            (run-program (● (● after first) reset)))
          (when (= (remainder step 10) 0) (work-done))
          (when (= (remainder step 50) 0) (shown (● after first)))
          (Run-step-set (Run-live-set (Run-programs-set run (● after first)) (● after second))
                        (+ step 1)))))

    ;; The step's loss, the gaussians live and the entries they were
    ;; binned into, each against its capacity, and the seconds so far.
    (define (report (run Run) (p Programs)) (→ Unit) (! clock gpu output-port tasks)
      (let ((loss (scalar-of (read-sink (● p step) 0)))
            (entries (f64->i64 (scalar-of (read-sink (● p step) 2))))
            (seconds (/ (i64->f64 (- (monotonic-nanoseconds) (● run started))) 1000000000.0)))
        (write-line (string-append "step " (show (● run step))
                                   " loss " (f64->string loss)
                                   " gaussians " (show (● run live)) "/" (show (● p capacity))
                                   " entries " (show entries) "/" (show (● p sensor capacity))
                                   " seconds " (f64->string seconds)))))

    ;; ---- Judging ----

    ;; The mean PSNR over the held-out photographs, each rendered from its
    ;; camera by a program on the trained params and clamped to 1, as the
    ;; reference measures.
    (define (held-out-psnr (p Programs) (scene Scene)) (→ F64) (! dataset gpu tasks)
      (let* ((cloud (splat-params (● p capacity)))
             (sensor (● p sensor))
             (target (rgba8-image (param "target"
                                         (list (● sensor height) (texel-pitch (● sensor width)))
                                         (Unsigned))
                                  (● sensor width)))
             (drawn (minimum (● (render cloud (camera-param) sensor) image) (scalar 1.0)))
             (error (mean (square (- drawn target))))
             (program (compile-program-sharing "judge" (list error) (Nil) (● p step)))
             (psnrs (map (lambda (image)
                           (let ((photo (photograph (● scene photographs) image)))
                             (aim program sensor scene image photo)
                             (destroy (TextureObject (● photo texture))))
                           (run-program program)
                           (* -10.0 (/ (log (scalar-of (read-sink program 0))) (log 10.0))))
                         (● scene held))))
        (release-program program)
        (/ (fold-left + 0.0 psnrs) (i64->f64 (length psnrs)))))

    ))
