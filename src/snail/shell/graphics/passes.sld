;; Full-screen passes over a G-buffer. `draw-sun`, in a pass begun with
;; `begin-lit` of (snail shell graphics raster), lights each pixel the
;; G-buffer has a surface at under the frame's sun and camera
;; (sun.wgsl.scm), with the same lighting as a translucent surface; the
;; pass's cleared background shows where there is none. Its `Sunlight` is
;; made once, and relit when the G-buffer is remade.
;;
;; A frame is lit into a `Post`'s light target, `light-format` so a
;; highlight can be brighter than 1, and `draw-post` brings it to the
;; screen in two more passes: tone mapping into an 8-bit target, then FXAA
;; into the canvas (post.wgsl.scm). A `Post` is made once for the canvas's
;; format and size and a `Tone`, and resized with the canvas.
(define-library (snail shell graphics passes)
  (export
   Sunlight
   make-sunlight
   relight
   draw-sun
   light-format
   Post
   PostTargets
   Tone
   Neutral
   Filmic
   make-post
   resize-post
   draw-post)
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
                           (targets
                            (list (Some (new ColorTarget (format format) (blend (None)))))))))
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
                                          (TextureEntry 2 (● g albedo view))
                                          (TextureEntry 3 (● g normal view))
                                          (TextureEntry 4 (● g material view))
                                          (TextureEntry 5 (● g depth view)))))))

    ;; ---- Tone mapping and FXAA ----

    (define light-format (→ TextureFormat) (Rgba16Float))

    ;; How light becomes the screen's colors: `Neutral` for light already
    ;; in display terms, which keeps colors below 0.8 as they are;
    ;; `Filmic`, Hable's curve and sRGB encoding, for physical light.
    (enum Tone
      (Neutral)
      (Filmic))

    ;; The tone-mapping and FXAA pipelines, FXAA's sampler, and the targets
    ;; for the canvas's size.
    (record Post
      ((tone GpuRenderPipeline)
       (fxaa GpuRenderPipeline)
       (sampler GpuSampler)
       (targets PostTargets)))

    ;; The light the frame is lit into, the tone-mapped 8-bit target, and
    ;; the groups each pass reads them through.
    (record PostTargets
      ((light GpuTexture)
       (light-view GpuTextureView)
       (toned GpuTexture)
       (toned-view GpuTextureView)
       (tone-group GpuBindGroup)
       (fxaa-group GpuBindGroup)))

    (define (make-post (format TextureFormat) (width I32) (height I32) (curve Tone))
      (→ Post)
      (! gpu)
      (let* ((module
              (create-shader-module (new ShaderModuleDescriptor (label "post") (code post-shader))))
             (tone (screen-pipeline module
                                    (match curve
                                      ((Neutral) "tone_fragment")
                                      ((Filmic) "filmic_fragment"))
                                    (Rgba8Unorm)))
             (fxaa (screen-pipeline module "fxaa_fragment" format))
             (sampler (create-sampler (new SamplerDescriptor
                                        (label "post/bilinear")
                                        (mag-filter (Linear))
                                        (min-filter (Linear))
                                        (mipmap-filter (Nearest))
                                        (address (ClampToEdge))))))
        (new Post
          (tone tone)
          (fxaa fxaa)
          (sampler sampler)
          (targets (post-targets tone fxaa sampler width height)))))

    ;; Targets of the new size; the old go.
    (define (resize-post (post Post) (width I32) (height I32)) (→ Post) (! gpu)
      (let ((old (● post targets)))
        (for-each (lambda (group) (destroy (BindGroupObject group)))
                  (list (● old tone-group) (● old fxaa-group)))
        (for-each (lambda (view) (destroy (ViewObject view)))
                  (list (● old light-view) (● old toned-view)))
        (for-each (lambda (texture) (destroy (TextureObject texture)))
                  (list (● old light) (● old toned)))
        (Post-targets-set post
                          (post-targets (● post tone)
                                        (● post fxaa)
                                        (● post sampler)
                                        width
                                        height))))

    (define (post-targets (tone GpuRenderPipeline)
                          (fxaa GpuRenderPipeline)
                          (sampler GpuSampler)
                          (width I32)
                          (height I32))
      (→ PostTargets)
      (! gpu)
      (let* ((light (screen-target "post/light" width height light-format))
             (toned (screen-target "post/toned" width height (Rgba8Unorm)))
             (light-view (view-of light 1))
             (toned-view (view-of toned 1)))
        (new PostTargets
          (light light)
          (light-view light-view)
          (toned toned)
          (toned-view toned-view)
          (tone-group (screen-group "post/tone" tone (list (TextureEntry 0 light-view))))
          (fxaa-group (screen-group "post/fxaa"
                                    fxaa
                                    (list (TextureEntry 1 toned-view) (SamplerEntry 2 sampler)))))))

    ;; The light tone-mapped, then smoothed into `canvas`.
    (define (draw-post (encoder GpuCommandEncoder) (canvas GpuTextureView) (post Post))
      (→ Unit)
      (! gpu)
      (screen-pass encoder (● post targets toned-view) (● post tone) (● post targets tone-group))
      (screen-pass encoder canvas (● post fxaa) (● post targets fxaa-group)))

    ;; One triangle over `target`, every pixel of which it writes.
    (define (screen-pass (encoder GpuCommandEncoder)
                         (target GpuTextureView)
                         (pipeline GpuRenderPipeline)
                         (group GpuBindGroup))
      (→ Unit)
      (! gpu)
      (let ((pass (begin-render-pass encoder
                                     (new RenderPassDescriptor
                                       (colors (list (Some (new ColorAttachment
                                                             (view target)
                                                             (load (Clear (new Color
                                                                            (red 0.0)
                                                                            (green 0.0)
                                                                            (blue 0.0)
                                                                            (alpha 1.0))))
                                                             (store #t)))))
                                       (depth (None))))))
        (set-pipeline pass pipeline)
        (set-bind-group pass 0 group)
        (draw pass 3 1 0 0)
        (end-pass pass)))

    (define (screen-pipeline (module GpuShaderModule) (entry String) (format TextureFormat))
      (→ GpuRenderPipeline)
      (! gpu)
      (create-render-pipeline
       (new RenderPipelineDescriptor
         (label (string-append "post/" entry))
         (module module)
         (vertex-entry "post_vertex")
         (buffers (Nil))
         (fragment (Some (new FragmentState
                           (entry entry)
                           (targets
                            (list (Some (new ColorTarget (format format) (blend (None)))))))))
         (topology (TriangleList))
         (cull (CullNone))
         (depth (None)))))

    (define (screen-target (label String) (width I32) (height I32) (format TextureFormat))
      (→ GpuTexture)
      (! gpu)
      (create-texture (new TextureDescriptor
                        (label label)
                        (width width)
                        (height height)
                        (layers 1)
                        (mips 1)
                        (format format)
                        (usage (list (RenderAttachment) (TextureBinding) (StorageBinding))))))

    (define (screen-group (label String)
                          (pipeline GpuRenderPipeline)
                          (entries (List BindGroupEntry)))
      (→ GpuBindGroup)
      (! gpu)
      (create-bind-group (new BindGroupDescriptor
                           (label label)
                           (pipeline (RenderPipeline pipeline))
                           (group 0)
                           (entries entries))))

    ))
