;; Graphics checks shared by Node and the page. Each renders or computes
;; on the host device and reads its result back.
(define-library (gpu-test device)
  (export
   device-checks
   buffer-named
   texture-named
   texels
   two-texels)
  (import
   (snail core base)
   (snail core io)
   (snail shell resource)
   (snail shell task)
   (snail shell gpu)
   (snail shell graphics pod)
   (snail shell graphics mesh)
   (snail shell graphics raster)
   (snail shell graphics passes)
   (snail shell graphics scan)
   (snail shell graphics radix-sort)
   (snail shell graphics splat)
   (snail shell graphics splat-view)
   (only (snail shell graphics forward shaders) water-shader)
   (only (snail shell graphics kernel) compute-kernel kernel-group)
   (gpu-test forward)
   (gpu-test shaders))
  (begin

    ;; ---- Checks ----

    (define (device-checks (gpu Gpu) (out OutputPort) (resources Resources)) (→ Unit)
      (write-line out (forward-material-check gpu resources))
      (write-line out (string-append "decoded: " (texels (decoded-texels gpu))))
      (write-line out (string-append "scene: " (texels (scene-frame gpu (Neutral)))))
      (write-line out (string-append "filmic: " (texels (scene-frame gpu (Filmic)))))
      (write-line out (string-append "photographic: " (texels (scene-frame gpu (Photographic)))))
      (write-line out (string-append "squares: " (words (squares gpu))))
      (write-line out
                  (string-append "water normals: "
                                 (words (compute-words gpu
                                                       (string-append water-shader water-probe)
                                                       "water_main"
                                                       4
                                                       1))))
      (write-line out (string-append "scan: " (scan-frame gpu)))
      (write-line out (string-append "sort: " (sort-frame gpu)))
      (let ((splatted (splat-frames gpu)))
        (write-line out (string-append "splats: " (texels (● splatted first))))
        (write-line out (string-append "turned: " (texels (● splatted second)))))
      (let ((viewed (viewed-frames gpu)))
        (write-line out (string-append "viewed splats: " (texels (● viewed first))))
        (write-line out (string-append "viewed turned: " (texels (● viewed second)))))
      (write-line out (string-append "timed: " (timed-pass gpu))))

    ;; ---- Objects ----

    (define (buffer-named (gpu Gpu) (name String) (size I32) (usage (List BufferUsage)))
      (→ GpuBuffer)
      ((● gpu create-buffer) (new BufferDescriptor (label name) (size size) (usage usage))))

    (define (texture-named (gpu Gpu) (name String) (width I32) (height I32)) (→ GpuTexture)
      ((● gpu create-texture) (new TextureDescriptor
                                (label name)
                                (width width)
                                (height height)
                                (layers 1)
                                (mips 1)
                                (format (Rgba8Unorm))
                                (usage (list (RenderAttachment) (TextureCopySrc))))))

    ;; A red texel beside a green one, as a PNG.
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

    ;; The PNG's texels as the host decodes them: the browser, or
    ;; @napi-rs/canvas on Node.
    (define (decoded-texels (gpu Gpu)) (→ Bytes)
      (match ((● gpu decode-image) two-texels)
        ((Some image)
         (let ((readback (buffer-named gpu "image-readback" 256 (list (MapRead) (CopyDst))))
               (encoder ((● gpu create-command-encoder))))
           ((● gpu copy-texture-to-buffer) encoder
            (whole-texture (● image texture))
            readback
            0
            256
            2
            1)
           ((● gpu submit) (list ((● gpu finish) encoder)))
           (let ((read ((● gpu read-buffer) readback 0 8)))
             ((● gpu destroy) (BufferObject readback))
             ((● gpu destroy) (TextureObject (● image texture)))
             read)))
        ((None) (panic "the two texels did not decode"))))

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

    (define (tile (x F32) (color Vec4f) (glow F32)) (→ (Pair Mesh Instance))
      (new Pair
        (first (Tile))
        (second (new Instance
                  (place (new Vec4f (x x) (y 0.0) (z 0.0) (w 0.0)))
                  (scale (new Vec4f (x 1.0) (y 1.0) (z 2.0) (w glow)))
                  (color color)
                  (from (new Vec4f (x x) (y 0.0) (z 0.0) (w 0.0)))
                  (material (new Vec2f (x 0.0) (y 1.0)))))))

    (define (tiles (gpu Gpu) (r Raster)) (→ Surface)
      (make-surface gpu r
                    "tiles"
                    #f
                    solid
                    (meshes
                     (list (tile -0.5 (new Vec4f (x 1.0) (y 0.0) (z 0.0) (w 1.0)) 1.0)
                           (tile 0.5 (new Vec4f (x 1.0) (y 1.0) (z 1.0) (w 1.0)) 0.0)))))

    (define (looking-down (x F32)) (→ Camera3D)
      (camera-3d (new Vec3f (x x) (y 5.0) (z 0.0))
                 (new Vec3f (x x) (y 0.0) (z 0.0))
                 (Parallel 2.0)
                 1.0
                 1.0))

    (define (scene-frame (gpu Gpu) (curve Tone)) (→ Bytes)
      (let* ((target (texture-named gpu "scene" 4 4))
             (readback (buffer-named gpu "scene-readback" 1024 (list (MapRead) (CopyDst))))
             (r (make-forward-batches gpu light-format))
             (depth (make-plane gpu "scene-depth" 4 4 (Depth24Plus) (list (RenderAttachment))))
             (post (make-post gpu (Rgba8Unorm) 4 4 curve))
             (tiles (tiles gpu r))
             (encoder ((● gpu create-command-encoder))))
        (write-raster gpu r (looking-down 0.0) overhead)
        (let ((pass ((● gpu begin-render-pass) encoder
                     (new RenderPassDescriptor
                       (colors (list (Some (new ColorAttachment
                                             (view (● post targets light-view))
                                             (resolve (None))
                                             (load (Clear black))
                                             (store #t)))))
                       (depth (Some (new DepthAttachment
                                      (view (● depth view))
                                      (load (ClearDepth 1.0))
                                      (store #f))))))))
          (draw-surface gpu pass r tiles)
          ((● gpu end-pass) pass))
        (draw-post gpu encoder (view-of gpu target 1) post)
        ((● gpu copy-texture-to-buffer) encoder (whole-texture target) readback 0 256 4 4)
        ((● gpu submit) (list ((● gpu finish) encoder)))
        ((● gpu read-buffer) readback 0 16)))

    (define overhead
      (→ Sun)
      (new Sun (direction (new Vec4f (x 0.0) (y 1.0) (z 0.0) (w 0.0))) (ambient 0.6)))

    ;; 1 to 100, squared by 64-wide workgroups, two of them, and the first
    ;; four and the last read back.

    (define (squares (gpu Gpu)) (→ Bytes)
      (let ((bytes (compute-words gpu square "square_main" 100 2)))
        (array-append (subarray bytes 0 16) (subarray bytes 396 400))))

    (define (compute-words (gpu Gpu) (source String) (entry String) (count I64) (groups I32))
      (→ Bytes)
      (let* ((module ((● gpu create-shader-module)
                      (new ShaderModuleDescriptor (label entry) (code source))))
             (pipeline (compute-kernel gpu module entry entry))
             (size (* 4 (i64->i32 count)))
             (numbers (buffer-named gpu entry size (list (Storage) (CopySrc) (CopyDst))))
             (readback (buffer-named gpu "words-readback" size (list (MapRead) (CopyDst))))
             (group (kernel-group gpu pipeline 0 entry (list (BufferEntry 0 numbers 0 0))))
             (encoder ((● gpu create-command-encoder))) (pass ((● gpu begin-compute-pass) encoder)))
        ((● gpu write-buffer)
         numbers
         0
         (pack (shape) (map (lambda (n) (+ 1 (i64->i32 n))) (iota count))))
        ((● gpu set-compute-pipeline) pass pipeline)
        ((● gpu set-compute-bind-group) pass 0 group)
        ((● gpu dispatch-workgroups) pass groups 1 1)
        ((● gpu end-compute-pass) pass)
        ((● gpu copy-buffer-to-buffer) encoder numbers 0 readback 0 size)
        ((● gpu submit) (list ((● gpu finish) encoder)))
        (let ((bytes ((● gpu read-buffer) readback 0 size)))
          (for-each (● gpu destroy)
                    (list (BufferObject readback) (BufferObject numbers) (BindGroupObject group)
                          (ComputePipelineObject pipeline) (ModuleObject module)))
          bytes)))

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

    (define (storage-buffer (gpu Gpu) (name String) (count I64)) (→ GpuBuffer)
      (buffer-named gpu name (i64->i32 (* 4 count)) (list (Storage) (CopySrc) (CopyDst))))

    ;; The buffer's first `count` numbers, read back.

    (define (read-numbers (gpu Gpu) (buffer GpuBuffer) (count I64)) (→ Bytes)
      (let ((readback
             (buffer-named gpu
                           "numbers-readback"
                           (i64->i32 (* 4 count))
                           (list (MapRead) (CopyDst))))
            (encoder ((● gpu create-command-encoder))))
        ((● gpu copy-buffer-to-buffer) encoder buffer 0 readback 0 (i64->i32 (* 4 count)))
        ((● gpu submit) (list ((● gpu finish) encoder)))
        (let ((bytes ((● gpu read-buffer) readback 0 (i64->i32 (* 4 count)))))
          ((● gpu destroy) (BufferObject readback))
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

    (define (scan-frame (gpu Gpu)) (→ String)
      (let* ((count 300000)
             (numbers (storage-buffer gpu "scanned" count))
             (scan (make-scan gpu "test" numbers count))
             (encoder ((● gpu create-command-encoder)))
             (pass ((● gpu begin-compute-pass) encoder)))
        ((● gpu write-buffer) numbers
         0
         (pack (shape)
               (map (lambda (i) (i64->i32 (remainder i 3))) (iota count))))
        (dispatch-scan gpu pass scan)
        ((● gpu end-compute-pass) pass)
        ((● gpu submit) (list ((● gpu finish) encoder)))
        (let ((bytes (read-numbers gpu numbers count)))
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

    (define (sort-frame (gpu Gpu)) (→ String)
      (let* ((count 5000)
             (keys (storage-buffer gpu "sort-keys" count))
             (values (storage-buffer gpu "sort-values" count))
             (lane (new SortLane (keys keys) (values values)))
             (sorter (make-sorter gpu "test" lane lane count 32 (None)))
             (encoder ((● gpu create-command-encoder)))
             (pass ((● gpu begin-compute-pass) encoder)))
        ((● gpu write-buffer)
         keys
         0
         (pack (shape) (map (lambda (i) (as-i32 (test-key i))) (iota count))))
        ((● gpu write-buffer) values 0 (pack (shape) (map i64->i32 (iota count))))
        (dispatch-sort gpu pass sorter)
        ((● gpu end-compute-pass) pass)
        ((● gpu submit) (list ((● gpu finish) encoder)))
        (sort-verdict (read-numbers gpu keys count) (read-numbers gpu values count) count)))

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
    ;; to the right and 0.5 nearer, in front of the red one's edge, so no two
    ;; are at one depth, where the quads and the training renderer would
    ;; order them differently. The texels at 3.5 pixels left of the center,
    ;; the center, 4.5 right and 3.5 above, then again with the red one's
    ;; transform turned a quarter about z, which stands it up.

    (define (gaussian (scale Vec3f) (transform I32)) (→ Gaussian)
      (new Gaussian
        (position (new Vec3f (x 0.0) (y 0.0) (z 0.0)))
        (transform transform)
        (rotation (new Vec4h (x 0.0) (y 0.0) (z 0.0) (w 1.0)))
        (scale-opacity (new Vec4h (x (● scale x)) (y (● scale y)) (z (● scale z)) (w 1.0)))))

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

    (define splats-camera
      (→ SplatCamera)
      (splat-camera (new Vec3f (x 0.0) (y 0.0) (z 5.0))
                    (new Vec3f (x 0.0) (y 0.0) (z 0.0))
                    (new Vec3f (x 0.0) (y 1.0) (z 0.0))
                    1.0
                    16
                    16))

    (define (splat-texels (gpu Gpu) (splats Splats) (target GpuTexture) (readback GpuBuffer))
      (→ Bytes)
      (let ((encoder ((● gpu create-command-encoder))))
        (let ((pass ((● gpu begin-compute-pass) encoder)))
          (sort-splats gpu pass splats splats-camera)
          ((● gpu end-compute-pass) pass))
        (let ((pass ((● gpu begin-render-pass) encoder (cleared (view-of gpu target 1) black))))
          (draw-splats gpu pass splats)
          ((● gpu end-pass) pass))
        (four-texels gpu encoder target readback)))

    ;; The four texels the splat checks read, once the encoder is submitted.
    (define (four-texels (gpu Gpu)
                         (encoder GpuCommandEncoder)
                         (target GpuTexture)
                         (readback GpuBuffer))
      (→ Bytes)
      ((● gpu copy-texture-to-buffer) encoder (whole-texture target) readback 0 256 16 16)
      ((● gpu submit) (list ((● gpu finish) encoder)))
      (let ((bytes ((● gpu read-buffer) readback 0 4096)))
        (array-concatenate (map (lambda (texel)
                                  (subarray bytes
                                            (+ (* 256 (● texel second)) (* 4 (● texel first)))
                                            (+ (* 256 (● texel second))
                                               (* 4 (+ (● texel first) 1)))))
                                (list (new Pair (first 4) (second 8))
                                      (new Pair (first 8) (second 8))
                                      (new Pair (first 12) (second 8))
                                      (new Pair (first 8) (second 4)))))))

    (define (three-splats (gpu Gpu)) (→ Splats)
      ;; Straddle the projection's 256-wide workgroup boundary. Dropping the
      ;; final partial group changes the green and blue pixels.
      (let ((splats (make-splats gpu "test" (Rgba8Unorm) 258 3)))
        (write-cloud gpu splats
                     255
                     (pack-cloud (list (gaussian (new Vec3f (x 0.9) (y 0.3) (z 0.3)) 0)
                                       (gaussian (new Vec3f (x 0.2) (y 0.2) (z 0.2)) 2)
                                       (gaussian (new Vec3f (x 0.3) (y 0.3) (z 0.3)) 1))
                                 (list (flat 1.0 0.0 0.0) (flat 0.0 1.0 0.0) (flat 0.0 0.0 1.0))))
        (write-transforms gpu splats (list (moved 0.0 0.0) (moved 1.5 0.5) (moved 0.0 2.0)))
        splats))

    ;; Each frame drawn by `draw`, under the transforms, then with the red
    ;; one's turned.
    (define (posed-frames (gpu Gpu) (splats Splats) (draw (Fn → Bytes))) (→ (Pair Bytes Bytes))
      (let ((level (draw)))
        (write-transforms gpu splats (list quarter-turn))
        (new Pair (first level) (second (draw)))))

    (define (splat-frames (gpu Gpu)) (→ (Pair Bytes Bytes))
      (let ((splats (three-splats gpu))
            (target (texture-named gpu "splats" 16 16))
            (readback (buffer-named gpu "splats-readback" 4096 (list (MapRead) (CopyDst)))))
        (posed-frames gpu splats (lambda () (splat-texels gpu splats target readback)))))

    ;; The same, drawn by the training renderer.

    (define (viewed-frames (gpu Gpu)) (→ (Pair Bytes Bytes))
      (let* ((splats (three-splats gpu))
             (view (make-splat-view gpu splats (Rgba8Unorm) 16 16 64))
             (target (texture-named gpu "viewed" 16 16))
             (readback (buffer-named gpu "viewed-readback" 4096 (list (MapRead) (CopyDst))))
             (frames
              (posed-frames gpu splats (lambda () (viewed-texels gpu view target readback)))))
        (release-splat-view gpu view)
        frames))

    (define (viewed-texels (gpu Gpu) (view SplatView) (target GpuTexture) (readback GpuBuffer))
      (→ Bytes)
      (let ((encoder ((● gpu create-command-encoder))))
        (write-view-camera gpu view splats-camera)
        (let ((pass ((● gpu begin-compute-pass) encoder)))
          (encode-splat-view gpu pass view)
          ((● gpu end-compute-pass) pass))
        (let ((pass ((● gpu begin-render-pass) encoder (cleared (view-of gpu target 1) black))))
          (present-splat-view gpu pass view)
          ((● gpu end-pass) pass))
        (four-texels gpu encoder target readback)))

    ;; ---- Timestamps ----

    ;; A render pass that clears a texture, timed as it begins and as it
    ;; ends. A time on the device need only be plausible here: at least
    ;; none and under a second.
    (define (timed-pass (gpu Gpu)) (→ String)
      (let* ((target (texture-named gpu "timed" 4 4))
             (queries ((● gpu create-query-set) (new QuerySetDescriptor (label "timed") (count 2))))
             (encoder ((● gpu create-command-encoder)))
             (pass ((● gpu begin-timed-render-pass) encoder
                    (cleared (view-of gpu target 1) red)
                    (new TimestampWrites
                      (query-set queries)
                      (beginning 0)
                      (end 1)))))
        ((● gpu end-pass) pass)
        (let ((seconds (elapsed-seconds (submit-timed gpu encoder queries 2) 0 1)))
          ((● gpu destroy) (QuerySetObject queries))
          ((● gpu destroy) (TextureObject target))
          (if (and (>= seconds 0.0) (< seconds 1.0))
              "a render pass between 0 and 1 seconds"
              (f64->string seconds)))))

    (define (cleared (view GpuTextureView) (color Color)) (→ RenderPassDescriptor)
      (new RenderPassDescriptor
        (colors (list (Some (new ColorAttachment
                              (resolve (None))
                              (view view)
                              (load (Clear color))
                              (store #t)))))
        (depth (None))))

    (define red (→ Color) (new Color (red 1.0) (green 0.0) (blue 0.0) (alpha 1.0)))

    (define black (→ Color) (new Color (red 0.0) (green 0.0) (blue 0.0) (alpha 1.0)))
    ))
