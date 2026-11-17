;; The checks of the `gpu` effect that need only a device, neither a screen
;; nor an image decoder, so the page (tests/gpu/main.scm) and Node
;; (tests/gpu/node.scm) run them alike. Each writes its line: two tiles
;; rasterized into a G-buffer and lit by the sun, under each tone curve,
;; and their motion and ids; numbers squared in a compute pass; 300,000
;; numbers scanned and 5,000 keys sorted; three gaussians splatted under
;; two transform tables; tensor programs compiled and checked against the
;; CPU, and Adam fitting a line; and the differentiable splat renderer
;; checked against the paper's blending and its gradients against central
;; differences. tests/gpu/expected.mjs holds the lines.
(define-library (gpu-test device)
  (export
   device-checks
   buffer-named
   texture-named
   texels)
  (import
   (snail core base)
   (snail core io)
   (snail shell task)
   (snail shell gpu)
   (snail shell graphics pod)
   (snail shell graphics mesh)
   (snail shell graphics raster)
   (snail shell graphics passes)
   (snail shell graphics scan)
   (snail shell graphics radix-sort)
   (snail shell graphics splat)
   (gpu-test shaders)
   (gpu-test tensor)
   (gpu-test splat-train))
  (begin

    ;; ---- Checks ----

    (define (device-checks) (→ Unit) (! gpu tasks output-port)
      (write-line (string-append "scene: " (texels (scene-frame (Neutral)))))
      (write-line (string-append "filmic: " (texels (scene-frame (Filmic)))))
      (write-line (string-append "squares: " (words (compute-frame))))
      (write-line (string-append "planes: " (planes-frame)))
      (write-line (string-append "scan: " (scan-frame)))
      (write-line (string-append "sort: " (sort-frame)))
      (let ((splatted (splat-frames)))
        (write-line (string-append "splats: " (texels (● splatted first))))
        (write-line (string-append "turned: " (texels (● splatted second)))))
      (write-line (string-append "tensor: " (tensor-agreement)))
      (write-line (string-append "fitted: " (fitted-line)))
      (write-line (string-append "splat forward: " (splat-forward-check)))
      (write-line (string-append "splat gradients: " (splat-gradient-check)))
      (write-line (string-append "splat fit: " (splat-fit-check))))

    ;; ---- Objects ----

    (define (buffer-named (name String) (size I32) (usage (List BufferUsage))) (→ GpuBuffer) (! gpu)
      (create-buffer (new BufferDescriptor (label name) (size size) (usage usage))))

    (define (texture-named (name String) (width I32) (height I32)) (→ GpuTexture) (! gpu)
      (create-texture (new TextureDescriptor
                        (label name)
                        (width width)
                        (height height)
                        (layers 1)
                        (mips 1)
                        (format (Rgba8Unorm))
                        (usage (list (RenderAttachment) (TextureCopySrc))))))

    (define (texels (bytes Bytes)) (→ String)
      (string-join (map (lambda (byte) (show (u8->i32 byte))) (array->list bytes)) " "))

    ;; ---- Scenes ----

    ;; Two tiles seen straight down through a parallel lens, lit into the
    ;; light and brought into a 4x4 texture by tone mapping and FXAA: the left
    ;; one red and glowing, whose 1.0 the tone curve's shoulder brings down
    ;; to 0.9 and desaturates a little, and the right one white under only
    ;; ambient light of 0.6, under the curve's knee, so its texels are 153.
    ;; The edge between them is straight down the texture, along which FXAA
    ;; blends nothing.

    (define (tile (x F32) (color Vec4f) (glow F32) (id I32)) (→ (Pair Mesh Instance))
      (new Pair
        (first (Tile))
        (second (new Instance
                  (place (new Vec4f (x x) (y 0.0) (z 0.0) (w 0.0)))
                  (scale (new Vec4f (x 1.0) (y 1.0) (z 2.0) (w glow)))
                  (color color)
                  (from (new Vec4f (x x) (y 0.0) (z 0.0) (w 0.0)))
                  (material (new Vec2f (x 0.0) (y 1.0)))
                  (id id)))))

    (define (tiles (r Raster)) (→ Surface) (! gpu)
      (make-surface r
                    "tiles"
                    #f
                    solid
                    (meshes (list (tile -0.5 (new Vec4f (x 1.0) (y 0.0) (z 0.0) (w 1.0)) 1.0 16777217)
                                  (tile 0.5 (new Vec4f (x 1.0) (y 1.0) (z 1.0) (w 1.0)) 0.0 -1)))))

    (define (looking-down (x F32)) (→ Camera3D)
      (camera-3d (new Vec3f (x x) (y 5.0) (z 0.0))
                 (new Vec3f (x x) (y 0.0) (z 0.0))
                 (Parallel 2.0)
                 1.0
                 1.0))

    (define (scene-frame (curve Tone)) (→ Bytes) (! gpu tasks)
      (let* ((target (texture-named "scene" 4 4))
             (readback (buffer-named "scene-readback" 1024 (list (MapRead) (CopyDst))))
             (r (make-raster color-planes light-format))
             (g (make-gbuffer color-planes 4 4))
             (light (make-sunlight light-format g r))
             (post (make-post (Rgba8Unorm) 4 4 curve))
             (tiles (tiles r))
             (encoder (create-command-encoder)))
        (write-raster r (looking-down 0.0) overhead)
        (let ((pass (begin-gbuffer encoder g)))
          (draw-surface pass r tiles)
          (end-pass pass))
        (let ((pass (begin-lit encoder
                               (● post targets light-view)
                               (new Color (red 0.0) (green 0.0) (blue 0.0) (alpha 1.0))
                               g)))
          (draw-sun pass light)
          (end-pass pass))
        (draw-post encoder (view-of target 1) post)
        (copy-texture-to-buffer encoder (whole-texture target) readback 0 256 4 4)
        (submit (list (finish encoder)))
        (read-buffer readback 0 16)))

    ;; The same tiles into a G-buffer with every plane, the camera moved half a
    ;; tile right since the last frame, so the scene moved a quarter of the
    ;; texture left: the motion at the left pixel, and the ids of the pixels
    ;; two and three over, on the white tile and past it.

    (define (planes-frame) (→ String) (! gpu tasks)
      (let* ((all (new Planes (motion #t) (ids #t)))
             (r (make-raster all light-format))
             (g (make-gbuffer all 4 4))
             (tiles (tiles r))
             (readback (buffer-named "motion-readback" 4 (list (MapRead) (CopyDst))))
             (r (write-raster (write-raster r (looking-down 0.0) overhead)
                              (looking-down 0.5)
                              overhead))
             (encoder (create-command-encoder)))
        (let ((pass (begin-gbuffer encoder g)))
          (draw-surface pass r tiles)
          (end-pass pass))
        (match (● g motion)
          ((Some plane)
           (copy-texture-to-buffer encoder (whole-texture (● plane texture)) readback 0 256 1 1))
          ((None) (unit)))
        (submit (list (finish encoder)))
        (let ((motion (read-buffer readback 0 4)))
          (string-join (list (show (half motion 0))
                             (show (half motion 2))
                             (id-text (read-id g 0 0))
                             (id-text (read-id g 2 0))
                             (id-text (read-id g 3 0)))
                       " "))))

    (define overhead
      (→ Sun)
      (new Sun (direction (new Vec4f (x 0.0) (y 1.0) (z 0.0) (w 0.0))) (ambient 0.6)))

    (define (id-text (id (Option I32))) (→ String)
      (match id
        ((Some id) (show id))
        ((None) "none")))

    ;; The half float at `at`, little-endian.
    (define (half (bytes Bytes) (at I64)) (→ F64)
      (let* ((bits (+ (u8->i32 (array-ref bytes at)) (* 256 (u8->i32 (array-ref bytes (+ at 1))))))
             (sign (if (>= bits 32768) -1.0 1.0))
             (exponent (remainder (quotient bits 1024) 32))
             (fraction (i32->f64 (remainder bits 1024))))
        (if (= exponent 0)
            (* sign (* fraction (power-of-two -24)))
            (* sign (* (+ 1.0 (/ fraction 1024.0)) (power-of-two (- exponent 15)))))))

    (define (power-of-two (n I32)) (→ F64)
      (cond ((> n 0) (* 2.0 (power-of-two (- n 1))))
            ((< n 0) (/ (power-of-two (+ n 1)) 2.0))
            (else 1.0)))

    ;; 1 to 100, squared by 64-wide workgroups, two of them, and the first
    ;; four and the last read back.

    (define (compute-frame) (→ Bytes) (! gpu tasks)
      (let* ((module
              (create-shader-module (new ShaderModuleDescriptor (label "square") (code square))))
             (pipeline (create-compute-pipeline
                        (new ComputePipelineDescriptor
                          (label "square")
                          (module module)
                          (entry "square_main"))))
             (numbers (buffer-named "numbers" 400 (list (Storage) (CopySrc) (CopyDst))))
             (readback (buffer-named "numbers-readback" 400 (list (MapRead) (CopyDst))))
             (group (create-bind-group (new BindGroupDescriptor
                                         (label "square")
                                         (pipeline (ComputePipeline pipeline))
                                         (group 0)
                                         (entries (list (BufferEntry 0 numbers 0 0))))))
             (encoder (create-command-encoder))
             (pass (begin-compute-pass encoder)))
        (write-buffer numbers 0 (pack (shape) (map (lambda (n) (+ 1 (i64->i32 n))) (iota 100))))
        (set-compute-pipeline pass pipeline)
        (set-compute-bind-group pass 0 group)
        (dispatch-workgroups pass 2 1 1)
        (end-compute-pass pass)
        (copy-buffer-to-buffer encoder numbers 0 readback 0 400)
        (submit (list (finish encoder)))
        (let ((bytes (read-buffer readback 0 400)))
          (array-append (subarray bytes 0 16) (subarray bytes 396 400)))))

    (define (words (bytes Bytes)) (→ String)
      (string-join (map (lambda (index)
                          (show (fold-left (lambda (value byte)
                                             (+ (* value 256)
                                                (u8->i32
                                                 (array-ref bytes (+ (* 4 index) (- 3 byte))))))
                                           0
                                           (iota 4))))
                        (iota (quotient (array-length bytes) 4)))
                   " "))

    ;; ---- Scans, sorts and splats ----

    (define (storage-buffer (name String) (count I64)) (→ GpuBuffer) (! gpu)
      (buffer-named name (i64->i32 (* 4 count)) (list (Storage) (CopySrc) (CopyDst))))

    ;; The buffer's first `count` numbers, read back.

    (define (read-numbers (buffer GpuBuffer) (count I64)) (→ Bytes) (! gpu tasks)
      (let ((readback
             (buffer-named "numbers-readback" (i64->i32 (* 4 count)) (list (MapRead) (CopyDst))))
            (encoder (create-command-encoder)))
        (copy-buffer-to-buffer encoder buffer 0 readback 0 (i64->i32 (* 4 count)))
        (submit (list (finish encoder)))
        (let ((bytes (read-buffer readback 0 (i64->i32 (* 4 count)))))
          (destroy (BufferObject readback))
          bytes)))

    ;; Number `index` of the bytes, unsigned.

    (define (number-at (bytes Bytes) (index I64)) (→ I64)
      (fold-left (lambda (value byte)
                   (+ (* value 256)
                      (i32->i64 (u8->i32 (array-ref bytes (+ (* 4 index) (- 3 byte)))))))
                 0
                 (iota 4)))

    ;; i mod 3 for each of 300,000 numbers, scanned in three levels: the sum
    ;; before index 3q + r is 3q, and 1 more when r is 2.

    (define (scanned-before (index I64)) (→ I64)
      (+ (* 3 (quotient index 3)) (if (= (remainder index 3) 2) 1 0)))

    (define (scan-frame) (→ String) (! gpu tasks)
      (let* ((count 300000)
             (numbers (storage-buffer "scanned" count))
             (scan (make-scan "test" numbers count))
             (encoder (create-command-encoder))
             (pass (begin-compute-pass encoder)))
        (write-buffer numbers
                      0
                      (pack (shape) (map (lambda (i) (i64->i32 (remainder i 3))) (iota count))))
        (dispatch-scan pass scan)
        (end-compute-pass pass)
        (submit (list (finish encoder)))
        (let ((bytes (read-numbers numbers count)))
          (string-append (string-join (map (lambda (index) (show (number-at bytes index)))
                                           (list 0 1 2 3 511 512 513 262144 299999))
                                      " ")
                         (if (every?
                              (lambda (index) (= (number-at bytes index) (scanned-before index)))
                              (iota count))
                             " all"
                             " wrong")))))

    ;; 5,000 keys of 12 varying high bits, so many are equal and many are at
    ;; least 2^31, sorted with their indices as values.

    (define (test-key (index I64)) (→ I64)
      (* (quotient (modulo (* (+ index 1) 2654435761) 4294967296) 1048576) 1048576))

    (define (as-i32 (value I64)) (→ I32)
      (i64->i32 (if (>= value 2147483648) (- value 4294967296) value)))

    (define (sort-frame) (→ String) (! gpu tasks)
      (let* ((count 5000)
             (keys (storage-buffer "sort-keys" count))
             (values (storage-buffer "sort-values" count))
             (sorter (make-sorter "test" keys values count 32))
             (encoder (create-command-encoder))
             (pass (begin-compute-pass encoder)))
        (write-buffer keys 0 (pack (shape) (map (lambda (i) (as-i32 (test-key i))) (iota count))))
        (write-buffer values 0 (pack (shape) (map i64->i32 (iota count))))
        (dispatch-sort pass sorter)
        (end-compute-pass pass)
        (submit (list (finish encoder)))
        (sort-verdict (read-numbers keys count) (read-numbers values count) count)))

    ;; Whether each key is its value's, the keys ascend, equal keys keep their
    ;; values ascending, and every value appears once.

    (define (sort-verdict (keys Bytes) (values Bytes) (count I64)) (→ String)
      (let ((ordered (lambda (i)
                       (let ((a (number-at keys i)) (b (number-at keys (+ i 1))))
                         (or (< a b)
                             (and (= a b) (< (number-at values i) (number-at values (+ i 1)))))))))
        (string-join
         (list (if (every? (lambda (i) (= (number-at keys i) (test-key (number-at values i))))
                           (iota count))
                   "paired"
                   "unpaired")
               (if (every? ordered (iota (- count 1))) "sorted stable" "unsorted")
               (if (= (fold-left + 0 (map (lambda (i) (number-at values i)) (iota count)))
                      (quotient (* count (- count 1)) 2))
                   "permutation"
                   "lost"))
         " ")))

    ;; Three gaussians seen from z = 5 onto a 16x16 texture: a red one at the
    ;; origin, three times as wide as it is tall; a small green one moved by
    ;; its transform 2 nearer the eye, in front of it; and a blue one moved 1.5
    ;; to the right. The texels at 3.5 pixels left of the center, the center,
    ;; 4.5 right and 3.5 above, then again with the red one's transform turned
    ;; a quarter about z, which stands it up.

    (define (gaussian (scale Vec3f) (transform I32)) (→ Gaussian)
      (new Gaussian
        (position (new Vec3f (x 0.0) (y 0.0) (z 0.0)))
        (transform transform)
        (rotation (new Vec4f (x 0.0) (y 0.0) (z 0.0) (w 1.0)))
        (scale scale)
        (opacity 1.0)))

    ;; Degree-0 coefficients for a color: (color - 0.5) / C0.
    (define (flat (r F32) (g F32) (b F32)) (→ (List Vec3f))
      (let ((c (lambda (x) (/ (- x 0.5) 0.2820948))))
        (list (new Vec3f (x (c r)) (y (c g)) (z (c b))))))

    (define (moved (x F32) (z F32)) (→ Mat4x4f)
      (new Mat4x4f
        (x (new Vec4f (x 1.0) (y 0.0) (z 0.0) (w 0.0)))
        (y (new Vec4f (x 0.0) (y 1.0) (z 0.0) (w 0.0)))
        (z (new Vec4f (x 0.0) (y 0.0) (z 1.0) (w 0.0)))
        (w (new Vec4f (x x) (y 0.0) (z z) (w 1.0)))))

    (define quarter-turn
      (→ Mat4x4f)
      (new Mat4x4f
        (x (new Vec4f (x 0.0) (y 1.0) (z 0.0) (w 0.0)))
        (y (new Vec4f (x -1.0) (y 0.0) (z 0.0) (w 0.0)))
        (z (new Vec4f (x 0.0) (y 0.0) (z 1.0) (w 0.0)))
        (w (new Vec4f (x 0.0) (y 0.0) (z 0.0) (w 1.0)))))

    (define (splat-texels (splats Splats) (target GpuTexture) (readback GpuBuffer))
      (→ Bytes)
      (! gpu tasks)
      (let ((encoder (create-command-encoder)))
        (sort-splats encoder
                     splats
                     (splat-camera (new Vec3f (x 0.0) (y 0.0) (z 5.0))
                                   (new Vec3f (x 0.0) (y 0.0) (z 0.0))
                                   (new Vec3f (x 0.0) (y 1.0) (z 0.0))
                                   1.0
                                   16
                                   16))
        (let ((pass (begin-render-pass encoder
                                       (new RenderPassDescriptor
                                         (colors (list (Some (new ColorAttachment
                                                               (view (view-of target 1))
                                                               (load (Clear (new Color
                                                                              (red 0.0)
                                                                              (green 0.0)
                                                                              (blue 0.0)
                                                                              (alpha 1.0))))
                                                               (store #t)))))
                                         (depth (None))))))
          (draw-splats pass splats)
          (end-pass pass))
        (copy-texture-to-buffer encoder (whole-texture target) readback 0 256 16 16)
        (submit (list (finish encoder)))
        (let ((bytes (read-buffer readback 0 4096)))
          (array-concatenate (map (lambda (texel)
                                    (subarray bytes
                                              (+ (* 256 (● texel second)) (* 4 (● texel first)))
                                              (+ (* 256 (● texel second))
                                                 (* 4 (+ (● texel first) 1)))))
                                  (list (new Pair (first 4) (second 8))
                                        (new Pair (first 8) (second 8))
                                        (new Pair (first 12) (second 8))
                                        (new Pair (first 8) (second 4))))))))

    (define (splat-frames) (→ (Pair Bytes Bytes)) (! gpu tasks)
      (let ((splats (make-splats "test" (Rgba8Unorm) 3 3))
            (target (texture-named "splats" 16 16))
            (readback (buffer-named "splats-readback" 4096 (list (MapRead) (CopyDst)))))
        (write-cloud splats
                     0
                     (pack-cloud (list (gaussian (new Vec3f (x 0.9) (y 0.3) (z 0.3)) 0)
                                       (gaussian (new Vec3f (x 0.2) (y 0.2) (z 0.2)) 2)
                                       (gaussian (new Vec3f (x 0.3) (y 0.3) (z 0.3)) 1))
                                 (list (flat 1.0 0.0 0.0) (flat 0.0 1.0 0.0) (flat 0.0 0.0 1.0))))
        (write-transforms splats (list (moved 0.0 0.0) (moved 1.5 0.0) (moved 0.0 2.0)))
        (let ((level (splat-texels splats target readback)))
          (write-transforms splats (list quarter-turn))
          (new Pair (first level) (second (splat-texels splats target readback))))))
    ))
