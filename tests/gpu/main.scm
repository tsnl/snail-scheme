;; WebGPU through the `gpu` effect on a real device: a frame clears a 4x4
;; texture and the canvas and fills both with a uniform's red, from a
;; record deriving Pod and a shader printed from src/gpu-test/paint.wgsl.scm,
;; copies the
;; texture into a buffer that is read back, and decodes a two-texel PNG,
;; read back the same way. A second frame draws again with the objects the
;; first made.
;; Then an atlas's picture is drawn as quads, two tiles are rasterized
;; into a G-buffer and lit by the sun, and a compute pass squares numbers in
;; a storage buffer. Last, 300,000 numbers are scanned, 5,000 keys sorted,
;; and three gaussians splatted under two transform tables; tensor
;; programs are compiled and checked against the CPU. The page
;; reads its own index.html as bytes, and a file it lacks fails; the last
;; frame's work is waited for. tests/browser/gpu.mjs checks what it prints.
(import
 (snail core base)
 (snail core io)
 (snail shell task)
 (snail shell page)
 (snail shell gpu)
 (snail shell graphics pod)
 (snail shell graphics atlas)
 (snail shell graphics quad)
 (snail shell graphics mesh)
 (snail shell graphics raster)
 (snail shell graphics passes)
 (snail shell graphics scan)
 (snail shell graphics radix-sort)
 (snail shell graphics splat)
 (only (snail shell fetch) fetch fetch-bytes)
 (snail shell fetch page)
 (gpu-test shaders)
 (gpu-test tensor))

(record Paint
  ((color Vec4f))
  (deriving Pod))

(define paint-shape (→ (Shape Paint)) (shape))

(define shader (→ String) (string-append (declarations paint-shape) paint))

;; A red texel beside a green one.
(define two-texels
  #u8(137 80
          78
          71
          13
          10
          26
          10
          0
          0
          0
          13
          73
          72
          68
          82
          0
          0
          0
          2
          0
          0
          0
          1
          8
          6
          0
          0
          0
          244
          34
          127
          138
          0
          0
          0
          14
          73
          68
          65
          84
          120
          156
          99
          248
          207
          192
          240
          31
          4
          1
          16
          248
          3
          253
          78
          149
          193
          111
          0
          0
          0
          0
          73
          69
          78
          68
          174
          66
          96 130))

(define (pipeline-for (module GpuShaderModule) (format TextureFormat)) (→ GpuRenderPipeline) (! gpu)
  (create-render-pipeline
   (new RenderPipelineDescriptor
     (label "test")
     (module module)
     (vertex-entry "vertex_main")
     (buffers (Nil))
     (fragment (Some (new FragmentState
                       (entry "fragment_main")
                       (targets (list (Some (new ColorTarget (format format) (blend (None)))))))))
     (topology (TriangleList))
     (cull (CullNone))
     (depth (None)))))

(define (group-for (pipeline GpuRenderPipeline) (color GpuBuffer)) (→ GpuBindGroup) (! gpu)
  (create-bind-group (new BindGroupDescriptor
                       (label "test")
                       (pipeline (RenderPipeline pipeline))
                       (group 0)
                       (entries (list (BufferEntry 0 color 0 0))))))

(define (fill (encoder GpuCommandEncoder)
              (view GpuTextureView)
              (pipeline GpuRenderPipeline)
              (group GpuBindGroup))
  (→ Unit)
  (! gpu)
  (let ((pass (begin-render-pass encoder
                                 (new RenderPassDescriptor
                                   (colors (list (Some (new ColorAttachment
                                                         (view view)
                                                         (load (Clear (new Color
                                                                        (red 0.0)
                                                                        (green 0.0)
                                                                        (blue 1.0)
                                                                        (alpha 1.0))))
                                                         (store #t)))))
                                   (depth (None))))))
    (set-pipeline pass pipeline)
    (set-bind-group pass 0 group)
    (draw pass 3 1 0 0)
    (end-pass pass)))

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

;; What the first frame makes and the second uses again: the texture, the
;; image, the paint's uniform, a buffer to read back into, and a pipeline
;; and group for the texture and for the canvas.
(record Painting
  ((target GpuTexture)
   (target-view GpuTextureView)
   (image Image)
   (readback GpuBuffer)
   (offscreen GpuRenderPipeline)
   (offscreen-group GpuBindGroup)
   (onscreen GpuRenderPipeline)
   (onscreen-group GpuBindGroup)))

(define (painting (info DeviceInfo)) (→ Painting) (! gpu tasks)
  (let* ((module (create-shader-module (new ShaderModuleDescriptor (label "test") (code shader))))
         (target (texture-named "target" 4 4))
         (color (buffer-named "paint" 16 (list (Uniform) (CopyDst))))
         (offscreen (pipeline-for module (Rgba8Unorm)))
         (onscreen (pipeline-for module (● info format))))
    (write-buffer color
                  0
                  (pod-bytes paint-shape
                             (new Paint (color (new Vec4f (x 1.0) (y 0.0) (z 0.0) (w 1.0))))))
    (new Painting
      (target target)
      (target-view (view-of target 1))
      (image (decode-image two-texels))
      (readback (buffer-named "readback" 1280 (list (MapRead) (CopyDst))))
      (offscreen offscreen)
      (offscreen-group (group-for offscreen color))
      (onscreen onscreen)
      (onscreen-group (group-for onscreen color)))))

;; The texels of the texture's first row and the image's, each row copied
;; at 256 bytes, the alignment a copy into a buffer needs.

(define (frame (p Painting)) (→ (Pair Bytes Bytes)) (! gpu tasks)
  (let ((encoder (create-command-encoder)) (readback (● p readback)))
    (fill encoder (● p target-view) (● p offscreen) (● p offscreen-group))
    (fill encoder (view-of (● (current-texture) texture) 1) (● p onscreen) (● p onscreen-group))
    (copy-texture-to-buffer encoder (whole-texture (● p target)) readback 0 256 4 4)
    (copy-texture-to-buffer encoder (whole-texture (● p image texture)) readback 1024 256 2 1)
    (submit (list (finish encoder)))
    (new Pair (first (read-buffer readback 0 16)) (second (read-buffer readback 1024 8)))))

(define (texels (bytes Bytes)) (→ String)
  (string-join (map (lambda (byte) (show (u8->i32 byte))) (array->list bytes)) " "))

;; The two texels composed into an atlas with red swapped for blue, then
;; drawn as two quads across a 4x2 texture: blue on the left, green on the
;; right. The picture also reads back as a PNG data URL.

(define two-texel-picture
  (→ Picture)
  (new Picture
    (key 1)
    (version 1)
    (width 2)
    (height 1)
    (layers (lambda ()
              (list (new Layer
                      (source (new Source (key 1) (bytes (lambda () two-texels))))
                      (from (new Rect (x 0) (y 0) (width 2) (height 1)))
                      (x 0)
                      (y 0)
                      (swaps (list (new Pair (first 16711680) (second 255))))))))))

(define (texel-quad (atlas Atlas) (column I32) (x F32)) (→ Quad)
  (match (atlas-slot atlas 1)
    ((Some slot)
     (let ((place (slot-region slot (new Rect (x column) (y 0) (width 1) (height 1)))))
       (new Quad
         (center (new Vec2f (x x) (y 1.0)))
         (size (new Vec2f (x 2.0) (y 2.0)))
         (angle 0.0)
         (page (● place first))
         (region (● place second))
         (color (new Vec4f (x 1.0) (y 1.0) (z 1.0) (w 1.0))))))
    ((None) (panic "the picture has no slot"))))

(define (quads-frame) (→ (Pair Bytes String)) (! gpu tasks)
  (let* ((encoder (create-command-encoder))
         (atlas (atlas-pictures (make-atlas "test" 16 1) encoder (list two-texel-picture)))
         (target (texture-named "quads" 4 2))
         (readback (buffer-named "quads-readback" 512 (list (MapRead) (CopyDst))))
         (pass (begin-render-pass encoder
                                  (new RenderPassDescriptor
                                    (colors (list (Some (new ColorAttachment
                                                          (view (view-of target 1))
                                                          (load (Clear (new Color
                                                                         (red 0.0)
                                                                         (green 0.0)
                                                                         (blue 0.0)
                                                                         (alpha 0.0))))
                                                          (store #t)))))
                                    (depth (None))))))
    (draw-quads pass
                (make-quads "test" (Rgba8Unorm) (● atlas texture))
                (new View2D
                  (center (new Vec2f (x 2.0) (y 1.0)))
                  (extent (new Vec2f (x 4.0) (y 2.0)))
                  (pixels (new Vec2f (x 4.0) (y 2.0))))
                (list (texel-quad atlas 0 1.0) (texel-quad atlas 1 3.0)))
    (end-pass pass)
    (copy-texture-to-buffer encoder (whole-texture target) readback 0 256 4 2)
    (submit (list (finish encoder)))
    (let ((texels (read-buffer readback 0 16)))
      (new Pair
        (first texels)
        (second (atlas-url atlas 1 (new Rect (x 0) (y 0) (width 2) (height 1))))))))

;; Two tiles seen straight down through a parallel lens, lit into the
;; light and brought into a 4x4 texture by tone mapping and FXAA: the left
;; one red and glowing, whose 1.0 the tone curve's shoulder brings down
;; to 0.9 and desaturates a little, and the right one white under only
;; ambient light of 0.6, under the curve's knee, so its texels are 153.
;; The edge between them is straight down the texture, along which FXAA
;; blends nothing.

(define (tile (x F32) (color Vec4f) (glow F32) (id F32)) (→ (Pair Mesh Instance))
  (new Pair
    (first (Tile))
    (second (new Instance
              (place (new Vec4f (x x) (y 0.0) (z 0.0) (w 0.0)))
              (scale (new Vec4f (x 1.0) (y 1.0) (z 2.0) (w glow)))
              (color color)
              (from (new Vec4f (x x) (y 0.0) (z 0.0) (w 0.0)))
              (material (new Vec4f (x 0.0) (y 1.0) (z 0.0) (w id)))))))

(define (tiles (r Raster)) (→ Surface) (! gpu)
  (make-surface r
                "tiles"
                #f
                solid
                (meshes (list (tile -0.5 (new Vec4f (x 1.0) (y 0.0) (z 0.0) (w 1.0)) 1.0 7.0)
                              (tile 0.5 (new Vec4f (x 1.0) (y 1.0) (z 1.0) (w 1.0)) 0.0 9.0)))))

(define (looking-down (x F32)) (→ Camera3D)
  (camera-3d (new Vec3f (x x) (y 5.0) (z 0.0))
             (new Vec3f (x x) (y 0.0) (z 0.0))
             (Parallel 2.0)
             1.0
             1.0))

(define (scene-frame) (→ Bytes) (! gpu tasks)
  (let* ((target (texture-named "scene" 4 4))
         (readback (buffer-named "scene-readback" 1024 (list (MapRead) (CopyDst))))
         (r (make-raster color-planes light-format))
         (g (make-gbuffer color-planes 4 4))
         (light (make-sunlight light-format g r))
         (post (make-post (Rgba8Unorm) 4 4))
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
         (r (write-raster (write-raster r (looking-down 0.0) overhead) (looking-down 0.5) overhead))
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
  (let* ((module (create-shader-module (new ShaderModuleDescriptor (label "square") (code square))))
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
                                            (u8->i32 (array-ref bytes (+ (* 4 index) (- 3 byte))))))
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
               (+ (* value 256) (i32->i64 (u8->i32 (array-ref bytes (+ (* 4 index) (- 3 byte)))))))
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
                     (if (every? (lambda (index) (= (number-at bytes index) (scanned-before index)))
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
                                          (+ (* 256 (● texel second)) (* 4 (+ (● texel first) 1)))))
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

;; ---- Files and waits ----

;; The page's first bytes, and why a missing file has none.

(define (fetched) (→ String) (! fetch tasks)
  (string-append (match (fetch-bytes "index.html")
                   ((Ok bytes)
                    (list->string (map (lambda (byte) (integer->char (i32->i64 (u8->i32 byte))))
                                       (array->list (subarray bytes 0 9)))))
                   ((Err message) message))
                 " "
                 (match (fetch-bytes "missing.bin")
                   ((Ok _) "found")
                   ((Err message) message))))

(with-page-fetch
 (lambda ()
   (let* ((info (request-device)) (p (painting info)))
     (write-line (string-append "format: " (texture-format-name (● info format))))
     (let ((first-frame (frame p)))
       (write-line (string-append "target: " (texels (● first-frame first))))
       (write-line (string-append "image: " (texels (● first-frame second)))))
     (let ((second-frame (frame p)))
       (write-line (string-append "again: " (texels (● second-frame first)))))
     (let ((quads (quads-frame)))
       (write-line (string-append "quads: " (texels (● quads first))))
       (write-line (string-append "url: " (● quads second))))
     (write-line (string-append "scene: " (texels (scene-frame))))
     (write-line (string-append "squares: " (words (compute-frame))))
     (write-line (string-append "planes: " (planes-frame)))
     (write-line (string-append "scan: " (scan-frame)))
     (write-line (string-append "sort: " (sort-frame)))
     (let ((splatted (splat-frames)))
       (write-line (string-append "splats: " (texels (● splatted first))))
       (write-line (string-append "turned: " (texels (● splatted second)))))
     (write-line (string-append "tensor: " (tensor-agreement)))
     (write-line (string-append "fitted: " (fitted-line)))
     (work-done)
     (write-line (string-append "fetched: " (fetched)))
     (report-ready))))
