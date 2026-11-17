;; Full-screen passes over a G-buffer. `sun-pass` clears a target to the
;; background and lights each pixel the G-buffer has a surface at under
;; the frame's sun and camera (sun.wgsl.scm), with the same lighting as a
;; translucent surface drawn by `raster-translucent`.
(define-library (snail shell graphics passes)
  (export
   sun-pass)
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

    (define (sun-pass (encoder GpuCommandEncoder)
                      (canvas GpuTexture)
                      (format TextureFormat)
                      (background Color)
                      (g GBuffer)
                      (r Raster))
      (→ Unit)
      (! gpu)
      (let ((pass (begin-render-pass encoder
                                     (new RenderPassDescriptor
                                       (colors (list (new ColorAttachment
                                                       (view (view-of canvas 1))
                                                       (load (Clear background))
                                                       (store #t))))
                                       (depth (None)))))
            (pipeline (sun-pipeline format)))
        (set-pipeline pass pipeline)
        (set-bind-group pass 0 (sun-group pipeline g r))
        (draw pass 3 1 0 0)
        (end-pass pass)))

    (define (sun-pipeline (format TextureFormat)) (→ GpuRenderPipeline) (! gpu)
      (create-render-pipeline
       (new RenderPipelineDescriptor
         (path (Some (list "passes" "sun" (texture-format-name format))))
         (module (create-shader-module
                  (new ShaderModuleDescriptor
                    (path (Some (list "passes" "sun")))
                    (code sun-code))))
         (vertex-entry "sun_vertex")
         (buffers (Nil))
         (fragment (Some (new FragmentState
                           (entry "sun_fragment")
                           (targets (list (new ColorTarget (format format) (blend (None))))))))
         (topology (TriangleList))
         (cull (CullNone))
         (depth (None)))))

    (define (sun-group (pipeline GpuRenderPipeline) (g GBuffer) (r Raster)) (→ GpuBindGroup) (! gpu)
      (create-bind-group (new BindGroupDescriptor
                           (path (Some (list "passes" "sun")))
                           (pipeline pipeline)
                           (group 0)
                           (entries (list (BufferEntry 0 (● r camera) 0 0)
                                          (BufferEntry 1 (● r sun) 0 0)
                                          (TextureEntry 2 (view-of (● g albedo) 1))
                                          (TextureEntry 3 (view-of (● g normal) 1))
                                          (TextureEntry 4 (view-of (● g material) 1))
                                          (TextureEntry 5 (view-of (● g depth) 1)))))))

    ))
