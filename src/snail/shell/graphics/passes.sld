;; Full-screen passes. A frame is lit into a `Post`'s light target,
;; `light-format` so a highlight can be brighter than 1, and `draw-post`
;; brings it to the screen in two more passes: tone mapping into an 8-bit
;; target, then FXAA into the canvas (post.wgsl.scm). A `Post` is made once for the canvas's
;; format and size and a `Tone`, and resized with the canvas.
(define-library (snail shell graphics passes)
  (export
   light-format
   Post
   PostTargets
   Tone
   Neutral
   Filmic
   Photographic
   make-post
   resize-post release-post
   draw-post screen-pass screen-group)
  (import
   (snail core base)
   (snail shell wire)
   (snail shell gpu)
   (only (snail shell graphics kernel) compute-kernel kernel-group dispatch-texels)
   (snail shell graphics shaders))
  (begin

    ;; ---- Tone mapping and FXAA ----

    (define light-format (→ TextureFormat) (Rgba16Float))

    ;; How light becomes the screen's colors: `Neutral` for light already
    ;; in display terms, which keeps colors below 0.8 as they are;
    ;; `Filmic` applies Hable's curve per channel. `Photographic` preserves
    ;; hue through the shoulder. Both encode scene-linear light as sRGB.
    (enum Tone
      (Neutral)
      (Filmic)
      (Photographic)
      (deriving Serialize Deserialize))

    ;; The tone curve and its pipeline, FXAA's pipeline and sampler, and
    ;; the targets for the canvas's size.
    (record Post
      ((curve Tone)
       (tone GpuComputePipeline)
       (fxaa GpuRenderPipeline)
       (sampler GpuSampler)
       (targets PostTargets)))

    ;; The light the frame is lit into, the tone-mapped 8-bit target, and
    ;; the groups each pass reads them through.
    (record PostTargets
      ((width I32)
       (height I32)
       (light GpuTexture)
       (light-view GpuTextureView)
       (toned GpuTexture)
       (toned-view GpuTextureView)
       (tone-group GpuBindGroup)
       (fxaa-group GpuBindGroup)))

    (define (make-post (gpu Gpu) (format TextureFormat) (width I32) (height I32) (curve Tone))
      (→ Post)
      (let* ((module
              ((● gpu create-shader-module)
               (new ShaderModuleDescriptor (label "post")
                    (code (string-append tone-shader post-shader)))))
             (tone (compute-kernel gpu module "post"
                                   (match curve
                                     ((Neutral) "tone_neutral")
                                     ((Filmic) "tone_filmic")
                                     ((Photographic) "tone_photographic"))))
             (fxaa (screen-pipeline gpu module "fxaa_fragment" format))
             (sampler ((● gpu create-sampler) (new SamplerDescriptor
                                                (label "post/bilinear")
                                                (mag-filter (Linear))
                                                (min-filter (Linear))
                                                (mipmap-filter (Nearest))
                                                (address (ClampToEdge))))))
        ((● gpu destroy) (ModuleObject module))
        (new Post
          (curve curve)
          (tone tone)
          (fxaa fxaa)
          (sampler sampler)
          (targets (post-targets gpu tone fxaa sampler width height)))))

    ;; Targets of the new size; the old go.
    (define (resize-post (gpu Gpu) (post Post) (width I32) (height I32)) (→ Post)
      (let ((old (● post targets)))
        (for-each (lambda (group) ((● gpu destroy) (BindGroupObject group)))
                  (list (● old tone-group) (● old fxaa-group)))
        (for-each (lambda (view) ((● gpu destroy) (ViewObject view)))
                  (list (● old light-view) (● old toned-view)))
        (for-each (lambda (texture) ((● gpu destroy) (TextureObject texture)))
                  (list (● old light) (● old toned)))
        (Post-targets-set post
                          (post-targets gpu (● post tone)
                                        (● post fxaa)
                                        (● post sampler)
                                        width
                                        height))))

    (define (release-post (gpu Gpu) (post Post)) (→ Unit)
      (let ((t (● post targets)))
        (for-each (lambda (obj) ((● gpu destroy) obj))
                  (list (ComputePipelineObject (● post tone))
                        (PipelineObject (● post fxaa))
                        (SamplerObject (● post sampler))
                        (BindGroupObject (● t tone-group)) (BindGroupObject (● t fxaa-group))
                        (ViewObject (● t light-view)) (ViewObject (● t toned-view))
                        (TextureObject (● t light)) (TextureObject (● t toned))))))
    (define (post-targets (gpu Gpu) (tone GpuComputePipeline)
                          (fxaa GpuRenderPipeline)
                          (sampler GpuSampler)
                          (width I32)
                          (height I32))
      (→ PostTargets)
      (let* ((light (screen-target gpu "post/light" width height light-format))
             (toned ((● gpu create-texture)
                     (new TextureDescriptor (label "post/toned") (width width) (height height)
                          (layers 1)
                          (mips 1)
                          (format (Rgba8Unorm))
                          (usage (list (StorageBinding) (TextureBinding))))))
             (light-view (view-of gpu light 1))
             (toned-view (view-of gpu toned 1)))
        (new PostTargets (width width) (height height)
             (light light)
             (light-view light-view)
             (toned toned)
             (toned-view toned-view)
             (tone-group (kernel-group gpu
                                       tone
                                       0
                                       "post/tone"
                                       (list (TextureEntry 0 light-view)
                                             (TextureEntry 3 toned-view))))
             (fxaa-group (screen-group gpu "post/fxaa"
                                       fxaa
                                       (list (TextureEntry 1 toned-view)
                                             (SamplerEntry 2 sampler)))))))

    ;; The light tone-mapped, then smoothed into `canvas`.
    (define (draw-post (gpu Gpu) (encoder GpuCommandEncoder) (canvas GpuTextureView) (post Post))
      (→ Unit)
      (let ((pass ((● gpu begin-compute-pass) encoder)))
        ((● gpu set-compute-pipeline) pass (● post tone))
        ((● gpu set-compute-bind-group) pass 0 (● post targets tone-group))
        (dispatch-texels gpu pass (● post targets width) (● post targets height))
        ((● gpu end-compute-pass) pass))
      (screen-pass gpu encoder canvas (● post fxaa) (● post targets fxaa-group)))

    ;; One triangle over `target`, every pixel of which it writes.
    (define (screen-pass (gpu Gpu) (encoder GpuCommandEncoder)
                         (target GpuTextureView)
                         (pipeline GpuRenderPipeline)
                         (group GpuBindGroup))
      (→ Unit)
      (let ((pass ((● gpu begin-render-pass) encoder
                   (new RenderPassDescriptor
                     (colors (list (Some (new ColorAttachment (resolve (None))
                                              (view target)
                                              (load (Clear (new Color
                                                             (red 0.0)
                                                             (green 0.0)
                                                             (blue 0.0)
                                                             (alpha 1.0))))
                                              (store #t)))))
                     (depth (None))))))
        ((● gpu set-pipeline) pass pipeline)
        ((● gpu set-bind-group) pass 0 group)
        ((● gpu draw) pass 3 1 0 0)
        ((● gpu end-pass) pass)))

    (define (screen-pipeline (gpu Gpu)
                             (module GpuShaderModule)
                             (entry String)
                             (format TextureFormat))
      (→ GpuRenderPipeline)
      ((● gpu create-render-pipeline)
       (new RenderPipelineDescriptor
         (label (string-append "post/" entry))
         (module module)
         (vertex-entry "post_vertex")
         (buffers (Nil))
         (fragment (Some (new FragmentState
                           (entry entry)
                           (targets
                            (list (Some (new ColorTarget
                                          (format format)
                                          (blend (None)))))))))
         (topology (TriangleList))
         (cull (CullNone))
         (depth (None)))))

    (define (screen-target (gpu Gpu) (label String) (width I32) (height I32) (format TextureFormat))
      (→ GpuTexture)
      ((● gpu create-texture) (new TextureDescriptor
                                (label label)
                                (width width)
                                (height height)
                                (layers 1)
                                (mips 1)
                                (format format)
                                (usage
                                 (list (RenderAttachment) (TextureBinding) (TextureCopySrc))))))

    (define (screen-group (gpu Gpu) (label String)
                          (pipeline GpuRenderPipeline)
                          (entries (List BindGroupEntry)))
      (→ GpuBindGroup)
      ((● gpu create-bind-group) (new BindGroupDescriptor
                                   (label label)
                                   (pipeline (RenderPipeline pipeline))
                                   (group 0)
                                   (entries entries))))

    ))
