;; WebGPU through the `gpu` effect on a real device: a frame clears a 4x4
;; texture and the canvas and fills both with a uniform's red, copies the
;; texture into a buffer that is read back, and decodes a two-texel PNG,
;; read back the same way. A second frame finds every object by its path.
;; tests/browser/gpu.mjs checks what it prints.
(import
 (snail core base)
 (snail core io)
 (snail shell task)
 (snail shell page)
 (snail shell gpu))

(define shader
  "struct Paint { color: vec4f }
@group(0) @binding(0) var<uniform> paint: Paint;
@vertex fn vertex_main(@builtin(vertex_index) i: u32) -> @builtin(position) vec4f {
  let corners = array(vec2f(-1.0, -3.0), vec2f(3.0, 1.0), vec2f(-1.0, 1.0));
  return vec4f(corners[i], 0.0, 1.0);
}
@fragment fn fragment_main() -> @location(0) vec4f { return paint.color; }")

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

(define (f32-bytes (values (List F32))) (→ Bytes)
  (array-generate (* 4 (length values))
                  (lambda (index)
                    (i32->u8 (i32-and (i32-shift-right/logical
                                       (f32->bits (list-ref values (quotient index 4)))
                                       (i64->i32 (* 8 (remainder index 4))))
                                      255)))))

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

(define (paint (encoder GpuCommandEncoder)
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
    (write-buffer color 0 (f32-bytes (list 1.0 0.0 0.0 1.0)))
    (paint encoder
           (view-of target 1)
           (pipeline-for module (Rgba8Unorm) "offscreen")
           color
           "offscreen")
    (paint encoder
           (view-of (current-texture) 1)
           (pipeline-for module (● info format) "onscreen")
           color
           "onscreen")
    (copy-texture-to-buffer encoder (whole-texture target) readback 0 256 4 4)
    (copy-texture-to-buffer encoder (whole-texture (● image texture)) readback 1024 256 2 1)
    (submit (list (finish encoder)))
    (new Pair (first (read-buffer readback 0 16)) (second (read-buffer readback 1024 8)))))

(define (texels (bytes Bytes)) (→ String)
  (string-join (map (lambda (byte) (show (u8->i32 byte))) (array->list bytes)) " "))

(let ((info (request-device 67108864)))
  (write-line (string-append "format: " (texture-format-name (● info format))))
  (let ((first-frame (frame info)))
    (write-line (string-append "target: " (texels (● first-frame first))))
    (write-line (string-append "image: " (texels (● first-frame second)))))
  (let ((second-frame (frame info)))
    (write-line (string-append "again: " (texels (● second-frame first)))))
  (report-ready))
