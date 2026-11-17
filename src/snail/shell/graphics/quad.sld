;; 2D quads in world units under a 2D camera: each a rectangle turned by
;; its angle, showing a region of one page of a texture array, tinted, over
;; what is drawn before it. Corners snap to the target's pixels in the
;; vertex shader (quad.wgsl.scm). A run of quads sharing a texture is one
;; instanced draw, through a `Quads` made once for the texture and target:
;;
;;   (let ((quads (draw-quads pass quads view quad-list)))   ; quads from make-quads
;;     ...)
;;
;; A Quads draws one run a frame: its buffers are written before the
;; frame's commands run, so a second run's write would replace the first.
;; Its instance buffer grows in powers of two, so a run that grows by a few
;; replaces it rarely.
(define-library (snail shell graphics quad)
  (export
   Quad
   View2D
   View2D-pixels-set
   Quads
   make-quads
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

    (define quad-code (→ String) (string-append (declarations view-shape) quad-shader))

    ;; ---- Drawing ----

    ;; The pipeline for a target's format, the camera's uniform, the
    ;; instances with room for `room` quads, and the group binding the
    ;; camera and the pages.
    (record Quads
      ((pipeline GpuRenderPipeline)
       (camera GpuBuffer)
       (instances GpuBuffer)
       (room I64)
       (group GpuBindGroup)))

    (define (make-quads (label String) (format TextureFormat) (pages GpuTexture)) (→ Quads) (! gpu)
      (let ((pipeline (quad-pipeline format))
            (camera (create-buffer (new BufferDescriptor
                                     (label (string-append "quad/" label "/view"))
                                     (size (i64->i32 (stride view-shape)))
                                     (usage (list (Uniform) (CopyDst)))))))
        (new Quads
          (pipeline pipeline)
          (camera camera)
          (instances (instance-buffer 64))
          (room 64)
          (group (create-bind-group (new BindGroupDescriptor
                                      (label (string-append "quad/" label))
                                      (pipeline pipeline)
                                      (group 0)
                                      (entries (list (BufferEntry 0 camera 0 0)
                                                     (TextureEntry 1 (array-view pages))
                                                     (SamplerEntry 2 (nearest-sampler))))))))))

    (define (draw-quads (pass GpuRenderPass) (quads Quads) (view View2D) (run (List Quad)))
      (→ Quads)
      (! gpu)
      (if (null? run)
          quads
          (let ((quads (roomy quads (length run))))
            (write-buffer (● quads camera) 0 (pod-bytes view-shape view))
            (write-buffer (● quads instances) 0 (pack quad-shape run))
            (set-pipeline pass (● quads pipeline))
            (set-bind-group pass 0 (● quads group))
            (set-vertex-buffer pass 0 (● quads instances) 0)
            (draw pass 4 (i64->i32 (length run)) 0 0)
            quads)))

    ;; Room for `count` quads; the smaller buffer goes at the submit.

    (define (roomy (quads Quads) (count I64)) (→ Quads) (! gpu)
      (if (>= (● quads room) count)
          quads
          (let ((room (capacity (* 2 (● quads room)) count)))
            (destroy (BufferObject (● quads instances)))
            (Quads-room-set (Quads-instances-set quads (instance-buffer room)) room))))

    (define (capacity (room I64) (count I64)) (→ I64)
      (if (>= room count) room (capacity (* 2 room) count)))

    (define (instance-buffer (room I64)) (→ GpuBuffer) (! gpu)
      (create-buffer (new BufferDescriptor
                       (label "quad/instances")
                       (size (i64->i32 (* (stride quad-shape) room)))
                       (usage (list (Vertex) (CopyDst))))))

    (define (quad-pipeline (format TextureFormat)) (→ GpuRenderPipeline) (! gpu)
      (create-render-pipeline
       (new RenderPipelineDescriptor
         (label "quad")
         (module
          (create-shader-module (new ShaderModuleDescriptor (label "quad") (code quad-code))))
         (vertex-entry "quad_vertex")
         (buffers (list (vertex-layout quad-shape (PerInstance) 0)))
         (fragment (Some (new FragmentState
                           (entry "quad_fragment")
                           (targets (list (new ColorTarget (format format) (blend (Some over))))))))
         (topology (TriangleStrip))
         (cull (CullNone))
         (depth (None)))))

    (define (nearest-sampler) (→ GpuSampler) (! gpu)
      (create-sampler (new SamplerDescriptor
                        (label "quad/nearest")
                        (mag-filter (Nearest))
                        (min-filter (Nearest))
                        (mipmap-filter (Nearest))
                        (address (ClampToEdge)))))

    ))
