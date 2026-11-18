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
   Environment
   Hdr
   read-hdr
   hdr-environment
   sky-environment
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

    ;; Its radiance, rgba32float, and its table, r32float and a texel
    ;; wider and taller than the radiance.
    (record Environment
      ((radiance Plane)
       (table Plane)))

    ;; The kernels' uniform: the file's width and height and the
    ;; environment's, the factor between them, and the sky.
    (record EnvironmentShape
      ((size Vec4i)
       (factor Vec4i)
       (sun Vec4f)
       (sun-light Vec4f)
       (zenith Vec4f)
       (horizon Vec4f)
       (ground Vec4f))
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
    (define (hdr-environment (hdr Hdr) (max-width I64)) (→ Environment) (! gpu)
      (let* ((factor (quotient (+ (● hdr width) (- max-width 1)) max-width))
             (width (quotient (● hdr width) factor))
             (height (quotient (● hdr height) factor))
             (file (filled "environment/file" (padded (● hdr bytes))))
             (rows (filled "environment/rows" (● hdr rows)))
             (rgbe (storage "environment/rgbe" (* 4 (* (● hdr width) (● hdr height)))))
             (radiance (plane "environment/radiance" width height (Rgba32Float)))
             (uniform (shape-uniform (sized hdr width height factor)))
             (kernels (environment-kernels)))
        (let* ((encoder (create-command-encoder)) (pass (begin-compute-pass encoder)))
          (bound pass
                 kernels
                 "unrle"
                 (list (buffer 0 file) (buffer 1 rows) (buffer 2 rgbe) (buffer 3 uniform)))
          (dispatch-items pass (● hdr height) 64)
          (bound pass
                 kernels
                 "downsample"
                 (list (buffer 2 rgbe) (buffer 3 uniform) (TextureEntry 4 (● radiance view))))
          (dispatch-texels pass (i64->i32 width) (i64->i32 height))
          (end-compute-pass pass)
          (submit (list (finish encoder))))
        (for-each (lambda (spent) (destroy (BufferObject spent))) (list file rows rgbe uniform))
        (with-table kernels radiance width height)))

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
        (ground (zero))))

    (define (zero) (→ Vec4f) (new Vec4f (x 0.0) (y 0.0) (z 0.0) (w 0.0)))

    ;; A sky drawn `width` texels across and half as tall.
    (define (sky-environment (sky Sky) (width I64)) (→ Environment) (! gpu)
      (let* ((height (quotient width 2))
             (radiance (plane "environment/radiance" width height (Rgba32Float)))
             (uniform (shape-uniform (new EnvironmentShape
                                       (size (new Vec4i
                                               (x 0)
                                               (y 0)
                                               (z (i64->i32 width))
                                               (w (i64->i32 height))))
                                       (factor (new Vec4i (x 1) (y 0) (z 0) (w 0)))
                                       (sun (● sky sun))
                                       (sun-light (● sky sun-light))
                                       (zenith (● sky zenith))
                                       (horizon (● sky horizon))
                                       (ground (● sky ground)))))
             (kernels (environment-kernels)))
        (let* ((encoder (create-command-encoder)) (pass (begin-compute-pass encoder)))
          (bound pass kernels "sky" (list (buffer 3 uniform) (TextureEntry 4 (● radiance view))))
          (dispatch-texels pass (i64->i32 width) (i64->i32 height))
          (end-compute-pass pass)
          (submit (list (finish encoder))))
        (destroy (BufferObject uniform))
        (with-table kernels radiance width height)))

    ;; The radiance with its table: each row's distribution, then the
    ;; rows'.
    (define (with-table (kernels (List (Pair String GpuComputePipeline)))
                        (radiance Plane)
                        (width I64)
                        (height I64))
      (→ Environment)
      (! gpu)
      (let* ((table (plane "environment/table" (+ width 1) (+ height 1) (R32Float)))
             (sums (storage "environment/sums" (* 4 height)))
             (entries (list (TextureEntry 5 (● radiance view))
                            (buffer 6 sums)
                            (TextureEntry 7 (● table view)))))
        (let* ((encoder (create-command-encoder)) (pass (begin-compute-pass encoder)))
          (bound pass kernels "weigh" entries)
          (dispatch-items pass height 64)
          (bound pass kernels "marginal" entries)
          (dispatch-workgroups pass 1 1 1)
          (end-compute-pass pass)
          (submit (list (finish encoder))))
        (destroy (BufferObject sums))
        (for-each (lambda (named) (destroy (ComputePipelineObject (● named second)))) kernels)
        (new Environment (radiance radiance) (table table))))

    (define (release-environment (environment Environment)) (→ Unit) (! gpu)
      (for-each release-plane (list (● environment radiance) (● environment table))))

    ;; Group 2 of `pipeline`, a kernel that includes
    ;; `environment-light-shader`.
    (define (environment-group (pipeline GpuComputePipeline) (environment Environment))
      (→ GpuBindGroup)
      (! gpu)
      (kernel-group pipeline
                    2
                    "environment"
                    (list (TextureEntry 0 (● environment radiance view))
                          (TextureEntry 1 (● environment table view)))))

    ;; ---- Kernels ----

    (define (environment-kernels) (→ (List (Pair String GpuComputePipeline))) (! gpu)
      (let ((module (create-shader-module (new ShaderModuleDescriptor
                                            (label "environment")
                                            (code (string-append (declarations shape-shape)
                                                                 environment-shader))))))
        (map (lambda (entry)
               (new Pair (first entry) (second (compute-kernel module "environment" entry))))
             (list "unrle" "downsample" "sky" "weigh" "marginal"))))

    ;; The kernel `entry` set over `entries`, for the dispatch that
    ;; follows; its group goes at the submit.
    (define (bound (pass GpuComputePass)
                   (kernels (List (Pair String GpuComputePipeline)))
                   (entry String)
                   (entries (List BindGroupEntry)))
      (→ Unit)
      (! gpu)
      (let* ((kernel (match (assoc-ref kernels entry)
                       ((Some kernel) kernel)
                       ((None) (panic (string-append "environment: no kernel " entry)))))
             (group (kernel-group kernel 0 (string-append "environment/" entry) entries)))
        (set-compute-pipeline pass kernel)
        (set-compute-bind-group pass 0 group)
        (destroy (BindGroupObject group))))

    (define (buffer (binding I32) (b GpuBuffer)) (→ BindGroupEntry) (BufferEntry binding b 0 0))

    (define (shape-uniform (s EnvironmentShape)) (→ GpuBuffer) (! gpu)
      (uniform-buffer "environment/shape" (pod-bytes shape-shape s)))

    (define (storage (label String) (size I64)) (→ GpuBuffer) (! gpu)
      (storage-buffer label size (list (CopyDst))))

    (define (filled (label String) (bytes Bytes)) (→ GpuBuffer) (! gpu)
      (let ((b (storage label (array-length bytes))))
        (write-buffer b 0 bytes)
        b))

    (define (padded (bytes Bytes)) (→ Bytes)
      (let ((extra (remainder (- 4 (remainder (array-length bytes) 4)) 4)))
        (if (= extra 0) bytes (array-append bytes (make-array extra (i32->u8 0))))))

    (define (plane (label String) (width I64) (height I64) (format TextureFormat)) (→ Plane) (! gpu)
      (make-plane label
                  (i64->i32 width)
                  (i64->i32 height)
                  format
                  (list (StorageBinding) (TextureBinding))))

    ))
