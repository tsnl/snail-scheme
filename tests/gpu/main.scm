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
 (only (snail shell fetch) Fetch fetch-bytes)
 (gpu-test shaders)
 (gpu-test device))

(record Paint-uniform
  ((color Vec4f))
  (deriving Pod))

(define paint-shape (→ (Shape Paint-uniform)) (shape))

(define shader (→ String) (string-append (declarations paint-shape) paint))

(define (pipeline-for (gpu Gpu) (module GpuShaderModule) (format TextureFormat))
  (→ GpuRenderPipeline)
  (gpu::create-render-pipeline
   (new RenderPipelineDescriptor
     (label "test")
     (module module)
     (vertex-entry "vertex_main")
     (buffers (Nil))
     (fragment (Some (new FragmentState
                       (entry "fragment_main")
                       (targets (list (Some (new ColorTarget
                                              (format format)
                                              (blend (None)))))))))
     (topology (TriangleList))
     (cull (CullNone))
     (depth (None)))))

(define (group-for (gpu Gpu) (pipeline GpuRenderPipeline) (color GpuBuffer))
  (→ GpuBindGroup)
  (gpu::create-bind-group (new BindGroupDescriptor
                            (label "test")
                            (pipeline (RenderPipeline pipeline))
                            (group 0)
                            (entries (list (BufferEntry 0 color 0 0))))))

(define (fill (gpu Gpu) (encoder GpuCommandEncoder)
              (view GpuTextureView)
              (pipeline GpuRenderPipeline)
              (group GpuBindGroup))
  (→ Unit)
  (let ((pass (gpu::begin-render-pass encoder
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
    (gpu::set-pipeline pass pipeline)
    (gpu::set-bind-group pass 0 group)
    (gpu::draw pass 3 1 0 0)
    (gpu::end-pass pass)))

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

(define (painting (gpu Gpu) (info DeviceInfo)) (→ Painting)
  (let* ((module
          (gpu::create-shader-module (new ShaderModuleDescriptor (label "test") (code shader))))
         (target (texture-named gpu "target" 4 4))
         (color (buffer-named gpu "paint" 16 (list (Uniform) (CopyDst))))
         (offscreen (pipeline-for gpu module (Rgba8Unorm)))
         (onscreen (pipeline-for gpu module (● info format))))
    (gpu::write-buffer color
                       0
                       (pod-bytes paint-shape
                                  (new Paint-uniform
                                    (color (new Vec4f (x 1.0) (y 0.0) (z 0.0) (w 1.0))))))
    (new Painting
      (target target)
      (target-view (view-of gpu target 1))
      (image (match (gpu::decode-image two-texels)
               ((Some image) image)
               ((None) (panic "the two texels did not decode"))))
      (readback (buffer-named gpu "readback" 1280 (list (MapRead) (CopyDst))))
      (offscreen offscreen)
      (offscreen-group (group-for gpu offscreen color))
      (onscreen onscreen)
      (onscreen-group (group-for gpu onscreen color)))))

;; The texels of the texture's first row and the image's, each row copied
;; at 256 bytes, the alignment a copy into a buffer needs.

(define (frame (gpu Gpu) (p Painting)) (→ (Pair Bytes Bytes))
  (let ((encoder (gpu::create-command-encoder)) (readback (● p readback)))
    (fill gpu encoder (● p target-view) (● p offscreen) (● p offscreen-group))
    (fill gpu
          encoder
          (view-of gpu (● (gpu::current-texture) texture) 1)
          (● p onscreen)
          (● p onscreen-group))
    (gpu::copy-texture-to-buffer encoder (whole-texture (● p target)) readback 0 256 4 4)
    (gpu::copy-texture-to-buffer encoder (whole-texture (● p image texture)) readback 1024 256 2 1)
    (gpu::submit (list (gpu::finish encoder)))
    (new Pair
      (first (gpu::read-buffer readback 0 16))
      (second (gpu::read-buffer readback 1024 8)))))

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

(define (quads-frame (gpu Gpu)) (→ (Pair Bytes String))
  (let* ((encoder (gpu::create-command-encoder))
         (atlas (atlas-pictures gpu (make-atlas gpu "test" 16 1) encoder (list two-texel-picture)))
         (target (texture-named gpu "quads" 4 2))
         (readback (buffer-named gpu "quads-readback" 512 (list (MapRead) (CopyDst))))
         (pass (gpu::begin-render-pass encoder
                                       (new RenderPassDescriptor
                                         (colors (list (Some (new ColorAttachment
                                                               (view (view-of gpu target 1))
                                                               (load (Clear (new Color
                                                                              (red 0.0)
                                                                              (green 0.0)
                                                                              (blue 0.0)
                                                                              (alpha 0.0))))
                                                               (store #t)))))
                                         (depth (None))))))
    (draw-quads gpu pass
                (make-quads gpu "test" (Rgba8Unorm) (● atlas texture))
                (new View2D
                  (center (new Vec2f (x 2.0) (y 1.0)))
                  (extent (new Vec2f (x 4.0) (y 2.0)))
                  (pixels (new Vec2f (x 4.0) (y 2.0))))
                (list (texel-quad atlas 0 1.0) (texel-quad atlas 1 3.0)))
    (gpu::end-pass pass)
    (gpu::copy-texture-to-buffer encoder (whole-texture target) readback 0 256 4 2)
    (gpu::submit (list (gpu::finish encoder)))
    (let ((texels (gpu::read-buffer readback 0 16)))
      (new Pair
        (first texels)
        (second (atlas-url gpu atlas 1 (new Rect (x 0) (y 0) (width 2) (height 1))))))))

;; ---- Files and waits ----

;; The page's first bytes, and why a missing file has none.

(define (fetched (fetch Fetch)) (→ String)
  (string-append (match (fetch-bytes fetch "index.html")
                   ((Ok bytes)
                    (list->string (map (lambda (byte) (integer->char (i32->i64 (u8->i32 byte))))
                                       (array->list (subarray bytes 0 9)))))
                   ((Err message) message))
                 " "
                 (match (fetch-bytes fetch "missing.bin")
                   ((Ok _) "found")
                   ((Err message) message))))

(define (main (gpu Gpu) (fetch Fetch) (events Events) (out OutputPort)) (→ Unit)
  (let* ((info (gpu::request-device)) (p (painting gpu info)))
    (write-line out (string-append "format: " (texture-format-name (● info format))))
    (let ((first-frame (frame gpu p)))
      (write-line out (string-append "target: " (texels (● first-frame first))))
      (write-line out (string-append "image: " (texels (● first-frame second)))))
    (let ((second-frame (frame gpu p)))
      (write-line out (string-append "again: " (texels (● second-frame first)))))
    (let ((quads (quads-frame gpu)))
      (write-line out (string-append "quads: " (texels (● quads first))))
      (write-line out (string-append "url: " (● quads second))))
    (device-checks gpu out)
    (gpu::work-done)
    (write-line out (string-append "fetched: " (fetched fetch)))
    (events::report-ready))
  (unit))
