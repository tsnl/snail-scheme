;; A sampled fullscreen triangle copies between textures of different sizes
;; and color formats. Only this pipeline depends on the destination format.
(define-library (snail shell graphics compositor)
  (export Compositor make-compositor composite! present! release-compositor)
  (import
   (snail core base)
   (snail shell gpu)
   (only (snail shell graphics shaders) blit-shader)
   (only (snail shell graphics passes) screen-group screen-pass))
  (begin
    (record Compositor
      ((pipeline GpuRenderPipeline)
       (sampler GpuSampler)
       (bound (Option (Pair GpuTextureView GpuBindGroup)))))
    (define (make-compositor (gpu Gpu) (format TextureFormat)) (→ Compositor)
      (let* ((module ((● gpu create-shader-module)
                      (new ShaderModuleDescriptor (label "compositor") (code blit-shader))))
             (pipeline ((● gpu create-render-pipeline)
                        (new RenderPipelineDescriptor (label "compositor/blit") (module module)
                             (vertex-entry "blit_vertex") (buffers (Nil))
                             (fragment (Some (new FragmentState (entry "blit_fragment")
                                                  (targets (list (Some (new ColorTarget
                                                                         (format format)
                                                                         (blend (None)))))))))
                             (topology (TriangleList)) (cull (CullNone)) (depth (None)))))
             (sampler ((● gpu create-sampler) (new SamplerDescriptor (label "compositor/linear")
                                                   (mag-filter (Linear))
                                                   (min-filter (Linear))
                                                   (mipmap-filter (Nearest))
                                                   (address (ClampToEdge))))))
        ((● gpu destroy) (ModuleObject module))
        (new Compositor (pipeline pipeline) (sampler sampler) (bound (None)))))
    (define (source-group! (gpu Gpu) (c Compositor) (source GpuTextureView)) (→ GpuBindGroup)
      (let ((bind (lambda ()
                    (let ((g (screen-group gpu "compositor/input" (● c pipeline)
                                           (list (TextureEntry 0 source)
                                                 (SamplerEntry 1 (● c sampler))))))
                      (set! (● c bound) (Some (new Pair (first source) (second g)))) g))))
        (match (● c bound)
          ((Some (Pair view group)) (if (= (● source id) (● view id)) group
                                        (begin ((● gpu destroy) (BindGroupObject group)) (bind))))
          ((None) (bind)))))
    (define (composite! (gpu Gpu) (c Compositor) (encoder GpuCommandEncoder)
                        (source GpuTextureView) (target GpuTextureView)) (→ Unit)
                        (screen-pass gpu
                                     encoder
                                     target
                                     (● c pipeline)
                                     (source-group! gpu c source)))
    ;; The host owns the acquired surface image. Its temporary view is only
    ;; needed until this command buffer is submitted.
    (define (present! (gpu Gpu) (c Compositor) (encoder GpuCommandEncoder)
                      (source GpuTextureView) (surface Image)) (→ Unit)
                      (let ((view (view-of gpu (● surface texture) 1)))
                        (composite! gpu c encoder source view)
                        ((● gpu destroy) (ViewObject view))))
    (define (release-compositor (gpu Gpu) (c Compositor)) (→ Unit)
      (match (● c bound)
        ((Some item) ((● gpu destroy) (BindGroupObject (● item second))))
        (_ (unit)))
      ((● gpu destroy) (SamplerObject (● c sampler)))
      ((● gpu destroy) (PipelineObject (● c pipeline))))))
