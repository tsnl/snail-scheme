;; Light from all around a scene: an equirectangular environment, made
;; on the device from a Radiance HDR file (the format of Khronos's glTF
;; sample environments) or drawn from a sky with a sun, with the table
;; that samples it by its light. A path tracer includes
;; `environment-light-shader` and binds `environment-group` as group 2
;; to look the environment up and to sample it (environment-light.wgsl.scm).
;;
;;   (match (read-hdr bytes) ((Ok hdr) (hdr-environment hdr 4096)) ((Err why) ...))
;;   (sky-environment sky 2048)
;;
;; `read-hdr` reads a file's header and the start of each of its rows,
;; which is all that can be wrong with one, so a program reads its file
;; before it puts anything on the device; `hdr-environment` decodes its
;; pixels there a row a thread, then averages them down to at most
;; `max-width` texels across (environment.wgsl.scm).
(define-library (snail shell graphics environment)
  (export
   Sky
   Atmosphere make-atmosphere-light update-atmosphere!
   Environment
   Hdr
   read-hdr
   hdr-environment
   sky-environment
   SkyLight make-sky-light update-sky! release-sky-light
   environment-group
   release-environment)
  (import
   (snail core base)
   (snail shell gpu)
   (snail shell graphics pod)
   (snail shell graphics kernel)
   (snail shell graphics raster)
   (snail shell graphics shaders))
  (begin

    ;; The direction toward the sun, the cosine of its angular radius, and
    ;; the irradiance it gives a surface facing it; the sky's zenith and
    ;; horizon colors, and the ground's, each with a strength in w.
    (record Sky
      ((sun Vec4f)
       (sun-light Vec4f)
       (zenith Vec4f)
       (horizon Vec4f)
       (ground Vec4f)))

    ;; The direction to the sun, wind displacement in kilometres and
    ;; cloud cover in [0, 1]. A cover of zero gives a clear atmosphere.
    (record Atmosphere
      ((sun Vec3f)
       (wind Vec2f)
       (cover F32)))

    ;; Radiance and its cumulative sampling table, plus two texels holding
    ;; an optional solar disc's direction, angular radius and irradiance.
    (record Environment
      ((radiance Plane)
       (table Plane)
       (disc Plane)))

    ;; The kernels' uniform: the file's width and height and the
    ;; environment's, the factor between them, and the sky.
    (record EnvironmentShape
      ((size Vec4i)
       (factor Vec4i)
       (sun Vec4f)
       (sun-light Vec4f)
       (zenith Vec4f)
       (horizon Vec4f)
       (ground Vec4f)
       (weather Vec4f))
      (deriving Pod))

    (define shape-shape (→ (Shape EnvironmentShape)) (shape))

    ;; ---- Radiance HDR files ----

    ;; A file: its size, its bytes, and where each row starts, as
    ;; little-endian words.
    (record Hdr
      ((width I64)
       (height I64)
       (bytes Bytes)
       (rows Bytes)))

    ;; The header is lines up to an empty one, then the size as
    ;; `-Y height +X width`, rows top down; each row is run-length
    ;; encoded, starting 2, 2 and its width.
    (define (read-hdr (bytes Bytes)) (→ (Result Hdr String))
      (match (blank-line bytes 0)
        ((None) (Err "no end to the header"))
        ((Some at)
         (match (size-line bytes at)
           ((None) (Err "the size is not -Y height +X width"))
           ((Some (Pair size data))
            (let ((width (● size second)) (height (● size first)))
              (if (or (< width 8) (> width 32767))
                  (Err "rows this wide are not run-length encoded")
                  (match (row-starts bytes data width height)
                    ((Some rows)
                     (Ok (new Hdr (width width) (height height) (bytes bytes) (rows rows))))
                    ((None) (Err "a row is not run-length encoded"))))))))))

    (define (byte-at (bytes Bytes) (index I64)) (→ I64)
      (if (< index (array-length bytes)) (i32->i64 (u8->i32 (array-ref bytes index))) -1))

    ;; Just past the first "\n\n".
    (define (blank-line (bytes Bytes) (from I64)) (→ (Option I64))
      (cond ((>= (+ from 1) (array-length bytes)) (None))
            ((and (= (byte-at bytes from) 10) (= (byte-at bytes (+ from 1)) 10)) (Some (+ from 2)))
            (else (blank-line bytes (+ from 1)))))

    ;; The height and width, and where the pixels start.
    (define (size-line (bytes Bytes) (at I64)) (→ (Option (Pair (Pair I64 I64) I64)))
      (match (after-text bytes at "-Y ")
        ((Some at)
         (let ((height (digits bytes at 0)))
           (match (after-text bytes (● height second) " +X ")
             ((Some at)
              (let ((width (digits bytes at 0)))
                (if (= (byte-at bytes (● width second)) 10)
                    (Some (new Pair
                            (first (new Pair (first (● height first)) (second (● width first))))
                            (second (+ 1 (● width second)))))
                    (None))))
             ((None) (None)))))
        ((None) (None))))

    (define (after-text (bytes Bytes) (at I64) (text String)) (→ (Option I64))
      (let ((chars (string->array text)))
        (if (fold-left (lambda (same index)
                         (and same
                              (= (byte-at bytes (+ at index))
                                 (char->integer (array-ref chars index)))))
                       #t
                       (iota (array-length chars)))
            (Some (+ at (array-length chars)))
            (None))))

    ;; The number written at `at`, and where it ends.
    (define (digits (bytes Bytes) (at I64) (value I64)) (→ (Pair I64 I64))
      (let ((byte (byte-at bytes at)))
        (if (and (>= byte 48) (<= byte 57))
            (digits bytes (+ at 1) (+ (* value 10) (- byte 48)))
            (new Pair (first value) (second at)))))

    ;; Each row's start, found by stepping over its runs: four channels,
    ;; each `width` pixels of runs.
    (define (row-starts (bytes Bytes) (data I64) (width I64) (height I64)) (→ (Option Bytes))
      (let walk ((row 0) (at data) (starts (Nil)))
        (cond ((= row height) (Some (words (list->array (reverse starts)))))
              ((not (row-begins? bytes at width)) (None))
              (else (walk (+ row 1) (channels-end bytes (+ at 4) width 4) (Cons at starts))))))

    ;; Little-endian words.
    (define (words (values (Array I64))) (→ Bytes)
      (array-generate (* 4 (array-length values))
                      (lambda ((index I64)) (→ U8)
                        (i32->u8
                         (i64->i32 (remainder (quotient (array-ref values (quotient index 4))
                                                        (expt-256 (remainder index 4)))
                                              256))))))

    (define (row-begins? (bytes Bytes) (at I64) (width I64)) (→ Bool)
      (and (= (byte-at bytes at) 2)
           (= (byte-at bytes (+ at 1)) 2)
           (= (+ (* 256 (byte-at bytes (+ at 2))) (byte-at bytes (+ at 3))) width)))

    (define (channels-end (bytes Bytes) (at I64) (width I64) (left I64)) (→ I64)
      (if (= left 0) at (channels-end bytes (runs-end bytes at width) width (- left 1))))

    ;; Past the runs of one channel: a count over 128 repeats one byte, a
    ;; count up to 128 is that many bytes.
    (define (runs-end (bytes Bytes) (at I64) (left I64)) (→ I64)
      (if (<= left 0)
          at
          (let ((count (byte-at bytes at)))
            (if (> count 128)
                (runs-end bytes (+ at 2) (- left (- count 128)))
                (runs-end bytes (+ at (+ 1 count)) (- left (max count 1)))))))

    (define (expt-256 (k I64)) (→ I64) (if (= k 0) 1 (* 256 (expt-256 (- k 1)))))

    ;; ---- Making ----

    ;; The environment of an HDR file, averaged down by a whole factor to
    ;; at most `max-width` across.
    (define (hdr-environment (gpu Gpu) (hdr Hdr) (max-width I64)) (→ Environment)
      (let* ((factor (quotient (+ (● hdr width) (- max-width 1)) max-width))
             (width (quotient (● hdr width) factor))
             (height (quotient (● hdr height) factor))
             (file (filled gpu "environment/file" (padded (● hdr bytes))))
             (rows (filled gpu "environment/rows" (● hdr rows)))
             (rgbe (storage gpu "environment/rgbe" (* 4 (* (● hdr width) (● hdr height)))))
             (radiance (plane gpu "environment/radiance" width height (Rgba32Float)))
             (uniform (shape-uniform gpu (sized hdr width height factor)))
             (kernels (environment-kernels gpu (list "unrle" "downsample"))))
        (let* ((encoder ((● gpu create-command-encoder)))
               (pass ((● gpu begin-compute-pass) encoder)))
          (bound gpu pass
                 kernels
                 "unrle"
                 (list (buffer 0 file) (buffer 1 rows) (buffer 2 rgbe) (buffer 3 uniform)))
          (dispatch-items gpu pass (● hdr height) 64)
          (bound gpu pass
                 kernels
                 "downsample"
                 (list (buffer 2 rgbe) (buffer 3 uniform) (TextureEntry 4 (● radiance view))))
          (dispatch-texels gpu pass (i64->i32 width) (i64->i32 height))
          ((● gpu end-compute-pass) pass)
          ((● gpu submit) (list ((● gpu finish) encoder))))
        (for-each (lambda (spent) ((● gpu destroy) (BufferObject spent)))
                  (list file rows rgbe uniform))
        (with-table gpu kernels radiance width height)))

    (define (sized (hdr Hdr) (width I64) (height I64) (factor I64)) (→ EnvironmentShape)
      (new EnvironmentShape
        (size (new Vec4i
                (x (i64->i32 (● hdr width)))
                (y (i64->i32 (● hdr height)))
                (z (i64->i32 width))
                (w (i64->i32 height))))
        (factor (new Vec4i (x (i64->i32 factor)) (y 0) (z 0) (w 0)))
        (sun (zero))
        (sun-light (zero))
        (zenith (zero))
        (horizon (zero))
        (ground (zero))
        (weather (zero))))

    (define (zero) (→ Vec4f) (new Vec4f (x 0.0) (y 0.0) (z 0.0) (w 0.0)))

    ;; ---- Changing skies ----

    ;; Updating these same textures keeps the tracer's bindings and geometry.
    ;; Both the radiance and its sampling distribution belong to one sky.
    (record SkyLight
      ((environment Environment)
       (kernels (List (Pair String GpuComputePipeline)))
       (uniform GpuBuffer)
       (sums GpuBuffer)
       (width I64)))
    (define (sky-size (width I64)) (→ Vec4i)
      (new Vec4i (x 0) (y 0) (z (i64->i32 width)) (w (i64->i32 (quotient width 2)))))

    (define (sky-shape (sky Sky) (width I64)) (→ EnvironmentShape)
      (new EnvironmentShape
        (size (sky-size width))
        (factor (new Vec4i (x 1) (y 0) (z 0) (w 0)))
        (sun (● sky sun)) (sun-light (● sky sun-light))
        (zenith (● sky zenith)) (horizon (● sky horizon)) (ground (● sky ground))
        (weather (zero))))

    (define (atmosphere-shape (air Atmosphere) (width I64)) (→ EnvironmentShape)
      (new EnvironmentShape
        (size (sky-size width))
        (factor (new Vec4i (x 1) (y 0) (z 0) (w 0)))
        (sun (new Vec4f (x (● air sun x)) (y (● air sun y)) (z (● air sun z)) (w 0.9999892)))
        (sun-light (zero)) (zenith (zero)) (horizon (zero)) (ground (zero))
        (weather (new Vec4f (x (● air wind x)) (y (● air wind y)) (z (● air cover)) (w 1.0)))))

    (define (make-sky-light (gpu Gpu) (sky Sky) (width I64)) (→ SkyLight)
      (new-sky-light gpu width (sky-shape sky width) "sky"))

    (define (make-atmosphere-light (gpu Gpu) (air Atmosphere) (width I64)) (→ SkyLight)
      (new-sky-light gpu width (atmosphere-shape air width) "atmosphere"))

    (define (new-sky-light (gpu Gpu) (width I64) (s EnvironmentShape) (entry String)) (→ SkyLight)
      (let* ((h (quotient width 2))
             (env (new Environment
                    (radiance (plane gpu "environment/radiance" width h (Rgba32Float)))
                    (table (plane gpu "environment/table" (+ width 1) (+ h 1) (R32Float)))
                    (disc (plane gpu "environment/disc" 2 1 (Rgba32Float)))))
             (light (new SkyLight
                      (environment env)
                      (kernels (environment-kernels gpu (list "sky" "atmosphere" "solar_disc")))
                      (uniform (shape-uniform gpu s))
                      (sums (storage gpu "environment/sums" (* 4 h)))
                      (width width))))
        (bake-sky! gpu light s entry)
        light))

    (define (update-sky! (gpu Gpu) (light SkyLight) (sky Sky)) (→ Unit)
      (bake-sky! gpu light (sky-shape sky (● light width)) "sky"))

    (define (update-atmosphere! (gpu Gpu) (light SkyLight) (air Atmosphere)) (→ Unit)
      (bake-sky! gpu light (atmosphere-shape air (● light width)) "atmosphere"))

    (define (bake-sky! (gpu Gpu) (light SkyLight) (s EnvironmentShape) (entry String)) (→ Unit)
      (let* ((w (● light width)) (h (quotient w 2)) (e (● light environment))
             (encoder ((● gpu create-command-encoder))) (pass ((● gpu begin-compute-pass) encoder))
             (uniform (buffer 3 (● light uniform)))
             (entries (list (TextureEntry 5 (● e radiance view))
                            (buffer 6 (● light sums))
                            (TextureEntry 7 (● e table view)))))
        ((● gpu write-buffer) (● light uniform) 0 (pod-bytes shape-shape s))
        (bound gpu pass (● light kernels) entry (list uniform (TextureEntry 4 (● e radiance view))))
        (dispatch-texels gpu pass (i64->i32 w) (i64->i32 h))
        (bound gpu
               pass
               (● light kernels)
               "solar_disc"
               (list uniform (TextureEntry 8 (● e disc view))))
        ((● gpu dispatch-workgroups) pass 1 1 1)
        (bound gpu pass (● light kernels) "weigh" entries) (dispatch-items gpu pass h 64)
        (bound gpu pass (● light kernels) "marginal" entries)
        ((● gpu dispatch-workgroups) pass 1 1 1)
        ((● gpu end-compute-pass) pass) ((● gpu submit) (list ((● gpu finish) encoder)))))
    (define (release-sky-work (gpu Gpu) (light SkyLight)) (→ Unit)
      ((● gpu destroy) (BufferObject (● light sums)))
      ((● gpu destroy) (BufferObject (● light uniform)))
      (for-each (lambda (k) ((● gpu destroy) (ComputePipelineObject (● k second))))
                (● light kernels)))
    (define (release-sky-light (gpu Gpu) (light SkyLight)) (→ Unit)
      (release-sky-work gpu light) (release-environment gpu (● light environment)))
    (define (sky-environment (gpu Gpu) (sky Sky) (width I64)) (→ Environment)
      (let ((light (make-sky-light gpu sky width)))
        (release-sky-work gpu light)
        (● light environment)))

    ;; The radiance with its table: each row's distribution, then the
    ;; rows'.
    (define (with-table (gpu Gpu) (kernels (List (Pair String GpuComputePipeline)))
                        (radiance Plane)
                        (width I64)
                        (height I64))
      (→ Environment)
      (let* ((table (plane gpu "environment/table" (+ width 1) (+ height 1) (R32Float)))
             (sums (storage gpu "environment/sums" (* 4 height)))
             (entries (list (TextureEntry 5 (● radiance view))
                            (buffer 6 sums)
                            (TextureEntry 7 (● table view)))))
        (let* ((encoder ((● gpu create-command-encoder)))
               (pass ((● gpu begin-compute-pass) encoder)))
          (bound gpu pass kernels "weigh" entries)
          (dispatch-items gpu pass height 64)
          (bound gpu pass kernels "marginal" entries)
          ((● gpu dispatch-workgroups) pass 1 1 1)
          ((● gpu end-compute-pass) pass)
          ((● gpu submit) (list ((● gpu finish) encoder))))
        ((● gpu destroy) (BufferObject sums))
        (for-each (lambda (named) ((● gpu destroy) (ComputePipelineObject (● named second))))
                  kernels)
        (new Environment (radiance radiance) (table table)
             (disc (plane gpu "environment/disc" 2 1 (Rgba32Float))))))

    (define (release-environment (gpu Gpu) (environment Environment)) (→ Unit)
      (for-each (lambda (plane) (release-plane gpu plane))
                (list (● environment radiance) (● environment table) (● environment disc))))

    ;; Group 2 of `pipeline`, a kernel that includes
    ;; `environment-light-shader`.
    (define (environment-group (gpu Gpu) (pipeline GpuComputePipeline) (environment Environment))
      (→ GpuBindGroup)
      (kernel-group gpu pipeline
                    2
                    "environment"
                    (list (TextureEntry 0 (● environment radiance view))
                          (TextureEntry 1 (● environment table view))
                          (TextureEntry 2 (● environment disc view)))))

    ;; ---- Kernels ----

    (define (environment-kernels (gpu Gpu) (draw (List String)))
      (→ (List (Pair String GpuComputePipeline)))
      (let* ((module ((● gpu create-shader-module) (new ShaderModuleDescriptor (label "environment")
                                                        (code
                                                         (string-append (declarations shape-shape)
                                                                        environment-shader
                                                                        atmosphere-shader)))))
             (kernels (map (lambda (entry)
                             (new Pair
                               (first entry)
                               (second (compute-kernel gpu module "environment" entry))))
                           (append draw (list "weigh" "marginal")))))
        ((● gpu destroy) (ModuleObject module))
        kernels))

    ;; The kernel `entry` set over `entries`, for the dispatch that
    ;; follows; its group goes at the submit.
    (define (bound (gpu Gpu) (pass GpuComputePass)
                   (kernels (List (Pair String GpuComputePipeline)))
                   (entry String)
                   (entries (List BindGroupEntry)))
      (→ Unit)
      (let* ((kernel (match (assoc-ref kernels entry)
                       ((Some kernel) kernel)
                       ((None) (panic (string-append "environment: no kernel " entry)))))
             (group (kernel-group gpu kernel 0 (string-append "environment/" entry) entries)))
        ((● gpu set-compute-pipeline) pass kernel)
        ((● gpu set-compute-bind-group) pass 0 group)
        ((● gpu destroy) (BindGroupObject group))))

    (define (buffer (binding I32) (b GpuBuffer)) (→ BindGroupEntry) (BufferEntry binding b 0 0))

    (define (shape-uniform (gpu Gpu) (s EnvironmentShape)) (→ GpuBuffer)
      (uniform-buffer gpu "environment/shape" (pod-bytes shape-shape s)))

    (define (storage (gpu Gpu) (label String) (size I64)) (→ GpuBuffer)
      (storage-buffer gpu label size (list (CopyDst))))

    (define (filled (gpu Gpu) (label String) (bytes Bytes)) (→ GpuBuffer)
      (let ((b (storage gpu label (array-length bytes))))
        ((● gpu write-buffer) b 0 bytes)
        b))

    (define (padded (bytes Bytes)) (→ Bytes)
      (let ((extra (remainder (- 4 (remainder (array-length bytes) 4)) 4)))
        (if (= extra 0) bytes (array-append bytes (make-array extra (i32->u8 0))))))

    (define (plane (gpu Gpu) (label String) (width I64) (height I64) (format TextureFormat))
      (→ Plane)
      (make-plane gpu label
                  (i64->i32 width)
                  (i64->i32 height)
                  format
                  (list (StorageBinding) (TextureBinding))))

    ))
