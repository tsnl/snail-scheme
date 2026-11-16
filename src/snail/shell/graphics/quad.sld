;; 2D quads in world units under a 2D camera: each a rectangle turned by
;; its angle, showing a region of one page of a texture array, tinted, over
;; what is drawn before it. Corners snap to the target's pixels in the
;; vertex shader (quad.wgsl.scm). A run of quads sharing a texture is one
;; instanced draw:
;;
;;   (draw-quads pass "sprites" (Bgra8Unorm) view (atlas-texture atlas) quads)
;;
;; A run's name keys its buffers and bind group, and a frame writes each
;; buffer once, so runs in one frame have distinct names.
(define-library (snail shell graphics quad)
  (export
   Quad
   View2D
   draw-quads)
  (import
   (snail core base)
   (snail shell gpu)
   (snail shell graphics pod)
   (snail shell graphics shaders))
  (begin

    ;; ---- Quads ----

    ;; `region` is x, y, width and height in texels of page `page`, from its
    ;; top left; `color` multiplies each texel, so a white texel shows it.
    (record Quad
      ((center Vec2f)
       (size Vec2f)
       (angle F32)
       (page I32)
       (region Vec4f)
       (color Vec4f))
      (deriving Pod))

    ;; The camera: the world point at the target's center, how much of the
    ;; world the target shows across and up, and the target's size in
    ;; pixels.
    (record View2D
      ((center Vec2f)
       (extent Vec2f)
       (pixels Vec2f))
      (deriving Pod))

    (define quad-shape (→ (Shape Quad)) (shape))

    (define view-shape (→ (Shape View2D)) (shape))

    ;; ---- Drawing ----

    (define (draw-quads (pass GpuRenderPass)
                        (name String)
                        (format TextureFormat)
                        (view View2D)
                        (pages GpuTexture)
                        (quads (List Quad)))
      (→ Unit)
      (! gpu)
      (unless (null? quads)
        (let* ((pipeline (quad-pipeline format))
               (camera (quad-buffer name
                                    "view"
                                    (array-length (pod-bytes view))
                                    (list (Uniform) (CopyDst))))
               (instances (instance-buffer name quads)))
          (write-buffer camera 0 (pod-bytes view))
          (write-buffer instances 0 (pack quads))
          (set-pipeline pass pipeline)
          (set-bind-group pass 0 (quad-group name pipeline camera pages))
          (set-vertex-buffer pass 0 instances 0)
          (draw pass 4 (i64->i32 (length quads)) 0 0))))

    (define (quad-pipeline (format TextureFormat)) (→ GpuRenderPipeline) (! gpu)
      (create-render-pipeline
       (new RenderPipelineDescriptor
         (path (Some (list "quad" (texture-format-name format))))
         (module (create-shader-module
                  (new ShaderModuleDescriptor
                    (path (Some (list "quad" "shader")))
                    (code (string-append (declarations view-shape) quad-shader)))))
         (vertex-entry "quad_vertex")
         (buffers (list (vertex-layout quad-shape (PerInstance) 0)))
         (fragment (Some (new FragmentState
                           (entry "quad_fragment")
                           (targets (list (new ColorTarget (format format) (blend (Some over))))))))
         (topology (TriangleStrip))
         (cull (CullNone))
         (depth (None)))))

    (define (quad-buffer (name String) (part String) (size I64) (usage (List BufferUsage)))
      (→ GpuBuffer)
      (! gpu)
      (create-buffer (new BufferDescriptor
                       (path (Some (list "quad" name part)))
                       (size (i64->i32 size))
                       (usage usage))))

    ;; Room for the quads, in powers of two from 64, so a run that grows
    ;; by a few replaces its buffer rarely.

    (define (instance-buffer (name String) (quads (List Quad))) (→ GpuBuffer) (! gpu)
      (quad-buffer name
                   "instances"
                   (* (stride quad-shape) (capacity 64 (length quads)))
                   (list (Vertex) (CopyDst))))

    (define (capacity (room I64) (count I64)) (→ I64)
      (if (>= room count) room (capacity (* 2 room) count)))

    (define (quad-group (name String)
                        (pipeline GpuRenderPipeline)
                        (camera GpuBuffer)
                        (pages GpuTexture))
      (→ GpuBindGroup)
      (! gpu)
      (create-bind-group (new BindGroupDescriptor
                           (path (Some (list "quad" name)))
                           (pipeline pipeline)
                           (group 0)
                           (entries (list (BufferEntry 0 camera 0 0)
                                          (TextureEntry 1 (array-view pages))
                                          (SamplerEntry 2 (nearest-sampler)))))))

    (define (nearest-sampler) (→ GpuSampler) (! gpu)
      (create-sampler (new SamplerDescriptor
                        (path (Some (list "quad" "nearest")))
                        (mag-filter (Nearest))
                        (min-filter (Nearest))
                        (mipmap-filter (Nearest))
                        (address (ClampToEdge)))))

    ))
