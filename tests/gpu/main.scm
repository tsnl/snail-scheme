;; WebGPU through the `gpu` effect on a real device: a frame clears a 4x4
;; texture and the canvas and fills both with a uniform's red, from a
;; record deriving Pod and a shader printed from src/gpu-test/paint.wgsl.scm,
;; copies the
;; texture into a buffer that is read back, and decodes a two-texel PNG,
;; read back the same way. A second frame draws again with the objects the
;; first made.
;; Then an atlas's picture is drawn as quads, and the checks that need
;; only a device run, as they do on Node ((gpu-test device)). The page
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
 (only (snail shell fetch) fetch fetch-bytes)
 (snail shell fetch page)
 (gpu-test shaders)
 (gpu-test device))

(record Paint-uniform
  ((color Vec4f))
  (deriving Pod))

(define paint-shape (→ (Shape Paint-uniform)) (shape))

(define shader (→ String) (string-append (declarations paint-shape) paint))

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
                             (new Paint-uniform
                               (color (new Vec4f (x 1.0) (y 0.0) (z 0.0) (w 1.0))))))
    (new Painting
      (target target)
      (target-view (view-of target 1))
      (image (match (decode-image two-texels)
               ((Some image) image)
               ((None) (panic "the two texels did not decode"))))
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
     (device-checks)
     (work-done)
     (write-line (string-append "fetched: " (fetched)))
     (report-ready))))
