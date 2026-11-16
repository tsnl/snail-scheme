;; WebGPU through the `gpu` effect on a real device: a frame clears a 4x4
;; texture and the canvas and fills both with a uniform's red, from a
;; record deriving Pod and a shader printed from src/gpu-test/paint.wgsl.scm,
;; copies the
;; texture into a buffer that is read back, and decodes a two-texel PNG,
;; read back the same way. A second frame finds every object by its path.
;; tests/browser/gpu.mjs checks what it prints.
(import
 (snail core base)
 (snail core io)
 (snail shell task)
 (snail shell page)
 (snail shell gpu)
 (snail shell graphics pod)
 (snail shell graphics atlas)
 (snail shell graphics quad)
 (gpu-test shaders))

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

(define (pipeline-for (module GpuShaderModule) (format TextureFormat) (name String))
  (→ GpuRenderPipeline)
  (! gpu)
  (create-render-pipeline
   (new RenderPipelineDescriptor
     (path (Some (list "test" name)))
     (module module)
     (vertex-entry "vertex_main")
     (buffers (Nil))
     (fragment (Some (new FragmentState
                       (entry "fragment_main")
                       (targets (list (new ColorTarget (format format) (blend (None))))))))
     (topology (TriangleList))
     (cull (CullNone))
     (depth (None)))))

(define (fill (encoder GpuCommandEncoder)
              (view TextureView)
              (pipeline GpuRenderPipeline)
              (color GpuBuffer)
              (name String))
  (→ Unit)
  (! gpu)
  (let ((pass (begin-render-pass encoder
                                 (new RenderPassDescriptor
                                   (colors (list (new ColorAttachment
                                                   (view view)
                                                   (load (Clear (new Color
                                                                  (red 0.0)
                                                                  (green 0.0)
                                                                  (blue 1.0)
                                                                  (alpha 1.0))))
                                                   (store #t))))
                                   (depth (None))))))
    (set-pipeline pass pipeline)
    (set-bind-group pass
                    0
                    (create-bind-group (new BindGroupDescriptor
                                         (path (Some (list "test" name)))
                                         (pipeline pipeline)
                                         (group 0)
                                         (entries (list (BufferEntry 0 color 0 0))))))
    (draw pass 3 1 0 0)
    (end-pass pass)))

(define (buffer-named (name String) (size I32) (usage (List BufferUsage))) (→ GpuBuffer) (! gpu)
  (create-buffer (new BufferDescriptor (path (Some (list "test" name))) (size size) (usage usage))))

;; The texels of the texture's first row and the image's, each row copied
;; at 256 bytes, the alignment a copy into a buffer needs.

(define (frame (info DeviceInfo)) (→ (Pair Bytes Bytes)) (! gpu tasks output-port)
  (let* ((module (create-shader-module
                  (new ShaderModuleDescriptor (path (Some (list "test" "shader"))) (code shader))))
         (target (create-texture (new TextureDescriptor
                                   (path (Some (list "test" "target")))
                                   (width 4)
                                   (height 4)
                                   (layers 1)
                                   (mips 1)
                                   (format (Rgba8Unorm))
                                   (usage (list (RenderAttachment) (TextureCopySrc))))))
         (image (decode-image (list "test" "two-texels") two-texels))
         (color (buffer-named "paint" 16 (list (Uniform) (CopyDst))))
         (readback (buffer-named "readback" 1280 (list (MapRead) (CopyDst))))
         (encoder (create-command-encoder)))
    (write-line
     (string-append "fresh: " (show (● target fresh)) " " (show (● (● image texture) fresh))))
    (write-buffer color
                  0
                  (pod-bytes (new Paint (color (new Vec4f (x 1.0) (y 0.0) (z 0.0) (w 1.0))))))
    (fill encoder
          (view-of target 1)
          (pipeline-for module (Rgba8Unorm) "offscreen")
          color
          "offscreen")
    (fill encoder
          (view-of (● (current-texture) texture) 1)
          (pipeline-for module (● info format) "onscreen")
          color
          "onscreen")
    (copy-texture-to-buffer encoder (whole-texture target) readback 0 256 4 4)
    (copy-texture-to-buffer encoder (whole-texture (● image texture)) readback 1024 256 2 1)
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
         (target (create-texture (new TextureDescriptor
                                   (path (Some (list "test" "quads")))
                                   (width 4)
                                   (height 2)
                                   (layers 1)
                                   (mips 1)
                                   (format (Rgba8Unorm))
                                   (usage (list (RenderAttachment) (TextureCopySrc))))))
         (readback (buffer-named "quads-readback" 512 (list (MapRead) (CopyDst))))
         (pass (begin-render-pass encoder
                                  (new RenderPassDescriptor
                                    (colors (list (new ColorAttachment
                                                    (view (view-of target 1))
                                                    (load (Clear (new Color
                                                                   (red 0.0)
                                                                   (green 0.0)
                                                                   (blue 0.0)
                                                                   (alpha 0.0))))
                                                    (store #t))))
                                    (depth (None))))))
    (draw-quads pass
                "test"
                (Rgba8Unorm)
                (new View2D
                  (center (new Vec2f (x 2.0) (y 1.0)))
                  (extent (new Vec2f (x 4.0) (y 2.0)))
                  (pixels (new Vec2f (x 4.0) (y 2.0))))
                (atlas-texture atlas)
                (list (texel-quad atlas 0 1.0) (texel-quad atlas 1 3.0)))
    (end-pass pass)
    (copy-texture-to-buffer encoder (whole-texture target) readback 0 256 4 2)
    (submit (list (finish encoder)))
    (let ((texels (read-buffer readback 0 16)))
      (new Pair
        (first texels)
        (second (atlas-url atlas 1 (new Rect (x 0) (y 0) (width 2) (height 1))))))))

(let ((info (request-device 67108864)))
  (write-line (string-append "format: " (texture-format-name (● info format))))
  (let ((first-frame (frame info)))
    (write-line (string-append "target: " (texels (● first-frame first))))
    (write-line (string-append "image: " (texels (● first-frame second)))))
  (let ((second-frame (frame info)))
    (write-line (string-append "again: " (texels (● second-frame first)))))
  (let ((quads (quads-frame)))
    (write-line (string-append "quads: " (texels (● quads first))))
    (write-line (string-append "url: " (● quads second))))
  (report-ready))
