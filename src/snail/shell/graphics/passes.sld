;; Full-screen passes over a G-buffer. `draw-sun`, in a pass begun with
;; `begin-lit` of (snail shell graphics raster), lights each pixel the
;; G-buffer has a surface at under the frame's sun and camera
;; (sun.wgsl.scm), with the same lighting as a translucent surface; the
;; pass's cleared background shows where there is none. Its `Sunlight` is
;; made once, and relit when the G-buffer is remade.
(define-library (snail shell graphics passes)
  (export
   Sunlight
   make-sunlight
   relight
   draw-sun)
  (import
   (snail core base)
   (snail shell gpu)
   (snail shell graphics pod)
   (snail shell graphics raster)
   (snail shell graphics shaders))
  (begin

    (define camera-shape (→ (Shape Camera3D)) (shape))
    (define sun-shape (→ (Shape Sun)) (shape))

    (define sun-code
      (→ String)
      (string-append (declarations camera-shape)
                     (declarations sun-shape)
                     lighting-shader
                     sun-shader))

    ;; The sun's pipeline on a target of `format`, and its bind group over
    ;; a G-buffer and a raster's camera and sun.
    (record Sunlight
      ((pipeline GpuRenderPipeline)
       (group GpuBindGroup)))

    (define (make-sunlight (format TextureFormat) (g GBuffer) (r Raster)) (→ Sunlight) (! gpu)
      (let ((pipeline (sun-pipeline format)))
        (new Sunlight (pipeline pipeline) (group (sun-group pipeline g r)))))

    ;; The same sunlight over another G-buffer; the old group goes.
    (define (relight (light Sunlight) (g GBuffer) (r Raster)) (→ Sunlight) (! gpu)
      (destroy (BindGroupObject (● light group)))
      (Sunlight-group-set light (sun-group (● light pipeline) g r)))

    ;; One triangle over the whole target, untested by depth.
    (define (draw-sun (pass GpuRenderPass) (light Sunlight)) (→ Unit) (! gpu)
      (set-pipeline pass (● light pipeline))
      (set-bind-group pass 0 (● light group))
      (draw pass 3 1 0 0))

    (define (sun-pipeline (format TextureFormat)) (→ GpuRenderPipeline) (! gpu)
      (create-render-pipeline
       (new RenderPipelineDescriptor
         (label "passes/sun")
         (module (create-shader-module
                  (new ShaderModuleDescriptor (label "passes/sun") (code sun-code))))
         (vertex-entry "sun_vertex")
         (buffers (Nil))
         (fragment (Some (new FragmentState
                           (entry "sun_fragment")
                           (targets (list (new ColorTarget (format format) (blend (None))))))))
         (topology (TriangleList))
         (cull (CullNone))
         (depth
          (Some (new DepthState (format (Depth24Plus)) (write #f) (compare (CompareAlways))))))))

    (define (sun-group (pipeline GpuRenderPipeline) (g GBuffer) (r Raster)) (→ GpuBindGroup) (! gpu)
      (create-bind-group (new BindGroupDescriptor
                           (label "passes/sun")
                           (pipeline (RenderPipeline pipeline))
                           (group 0)
                           (entries (list (BufferEntry 0 (● r camera) 0 0)
                                          (BufferEntry 1 (● r sun) 0 0)
                                          (TextureEntry 2 (● g albedo-view))
                                          (TextureEntry 3 (● g normal-view))
                                          (TextureEntry 4 (● g material-view))
                                          (TextureEntry 5 (● g depth-view)))))))

    ))
