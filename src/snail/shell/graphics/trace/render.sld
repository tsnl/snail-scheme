;; A scene path traced to the canvas, a frame at a time, composed of the
;; graphics middleware:
;;
;;   surfaces   the first hits, rasterized into a G-buffer, and the
;;              nearest blended surface in front of them into a second,
;;              the blended layer (surface.wgsl.scm)
;;   direct     biased first-hit sky and triangle sampling (trace/restir.wgsl.scm)
;;              with the accumulators of (snail shell graphics restir)
;;   paths      a wavefront of kernels (path.wgsl.scm), each bounce's rays
;;              traced by (snail shell graphics bvh)'s queries with the
;;              scene's cutouts (scene.wgsl.scm), lit by an environment
;;              of (snail shell graphics environment)
;;   filters    (snail shell graphics svgf) over the paths and the G-buffer,
;;              for each layer
;;   compose    the blended layer's light over the first hits', by its
;;              alpha (compose.wgsl.scm)
;;   optics     optional height fog with traced sun visibility and a
;;              depth-aware lens over the denoised HDR image
;;   post       (snail shell graphics passes)'s tone mapping and FXAA
;;
;; A `Tracer` is made once for a scene and the canvas, and resized with it:
;;
;;   (let ((sized (resize-tracer gpu (make-tracer gpu scene sky format w h 1024 (Filmic)) w h)))
;;     (draw-traced gpu sized canvas camera spread exposure 4 #f
;;                  (new TraceSettings (display-width w) (display-height h))))
;;
;; Each frame says how many bounces its paths make, up to `most-bounces`.
(define-library (snail shell graphics trace render)
  (export
   Tracer TracedView
   LightGuiding Tracer-guiding-set
   most-bounces
   TraceSettings
   encode-trace-observation
   make-tracer
   build-scene-bvh
   discard-trace-history
   refit-tracer!
   resize-tracer
   retrace retrace-built
   draw-traced draw-traced-samples with-photography
   tracer-frames)
  (import
   (snail core base)
   (snail shell gpu)
   (snail shell graphics pod)
   (snail shell graphics kernel)
   (snail shell graphics raster)
   (snail shell graphics passes)
   (snail shell graphics upscale)
   (snail shell graphics trace photography)
   (snail shell graphics bvh)
   (snail shell graphics restir)
   (snail shell graphics svgf)
   (snail shell graphics environment)
   (only (snail shell graphics shaders) environment-light-shader)
   (snail shell graphics trace scene)
   (snail shell graphics trace shaders))
  (begin

    ;; ---- Uniforms ----

    ;; Reuse is -1 for an independent observation, 0 for fresh proposals
    ;; with spatial reuse, 1 with a temporal donor, and 2 during motion.
    (record Tracing
      ((spread F32)
       (layer-size F32)
       (sample-index I32)
       (sample-weight F32)
       (frame I32)
       (layer-offset I32)
       (reuse I32))
      (deriving Pod))

    ;; A bounce's uniform, one slot each: its number and whether it is the
    ;; last; then the words of the counts it reads and appends to
    ;; (path.wgsl.scm).
    (record Wave
      ((step Vec4i)
       (slots Vec4i)
       (guiding GuidingRates))
      (deriving Pod))

    (define tracing-shape (→ (Shape Tracing)) (shape))
    (define wave-shape (→ (Shape Wave)) (shape))
    (define camera-shape (→ (Shape Camera3D)) (shape))
    (define material-shape (→ (Shape SurfaceMaterial)) (shape))

    ;; The most times a frame's paths may scatter, which the queues'
    ;; counts and the bounces' groups are made for.
    (define most-bounces (→ I64) 8)

    ;; ---- The tracer ----

    ;; A tracer's parts, one record for each lifetime, and the bind groups
    ;; over them. The bindings are always those of the kit, the world and
    ;; the targets beside them: `make-tracer` and `rebound` alone make a
    ;; Tracer, and both bind. Then the filters and post passes, the last
    ;; frame's camera and bounces, how many frames have held both still,
    ;; and how many have been drawn.
    (record Tracer
      ((kit Kit)
       (world World)
       (targets Targets)
       (bindings Bindings)
       (svgf Svgf)
       (blended-svgf (Option Svgf))
       (post Post)
       (upscale (Option Upscaler))
       (photography (Option Photography))
       (guiding LightGuiding)
       (last (Option TracedView))
       (bounces I64)
       (still I32)
       (frame I32)
       (sky-revision I64)))

    ;; Compare the game camera for movement. Reproject through the matrix
    ;; that actually rasterized the previous G-buffer, including its jitter.
    (record TracedView
      ((camera Camera3D)
       (raster Camera3D)
       (exposure F32)))

    ;; What is made once: the pipelines, the BVH's builder, the uniforms,
    ;; the queues' counts, and zeros to clear them with between the first
    ;; hits' paths and the blended layer's, whose `tracing` puts its
    ;; radiance past theirs.
    (record Kit
      ((opaque-surface GpuRenderPipeline)
       (surface GpuRenderPipeline)
       (blended-surface GpuRenderPipeline)
       (compose GpuRenderPipeline)
       (steps Steps)
       (rays RayKernels)
       (builder BvhBuilder)
       (camera GpuBuffer)
       (tracing GpuBuffer)
       (blended-tracing GpuBuffer)
       (sample-inputs GpuBuffer)
       (wave GpuBuffer)
       (counts GpuBuffer)
       (cleared-counts GpuBuffer)
       (layer-size I32)))

    ;; The path kernels, each its own pipeline.
    (record Steps
      ((temporal GpuComputePipeline)
       (primary GpuComputePipeline)
       (connect GpuComputePipeline)
       (shade GpuComputePipeline)
       (gather GpuComputePipeline)))

    ;; What is traced: the scene and the environment, which are the
    ;; caller's, and the scene's BVH, which is the tracer's. A scene that
    ;; moves (a MovingScene's) has a tree for each moving object, and
    ;; `refit-tracer!` follows them after each pose.
    (record World
      ((scene Scene)
       (bvh Bvh)
       (environment Environment)))

    ;; What the canvas's size sets: the G-buffer's planes and depth; the
    ;; noisy plane; the blended layer's own, for a scene with a blended
    ;; material; the queues, two of rays, which a bounce reads one of and
    ;; appends to the other, and one of shadow rays; and each path's
    ;; radiance, the first hits' then the blended layer's. A path makes at
    ;; most one ray and one shadow ray a bounce, and the blended layer's
    ;; paths run after the first hits', so a queue of a ray a pixel never
    ;; overflows.
    (record Targets
      ((width I32)
       (height I32)
       (planes (List Plane))
       (depth Plane)
       (noisy Plane)
       (blended (Option Blended))
       (temporal GpuBuffer)
       (history GpuBuffer)
       (queues (List GpuBuffer))
       (shadows GpuBuffer)
       (radiance GpuBuffer)))

    ;; The blended layer's own targets: its G-buffer's planes and depth,
    ;; its noisy plane, and the plane its light is filtered into.
    (record Blended
      ((planes (List Plane))
       (depth Plane)
       (noisy Plane)
       (history GpuBuffer)
       (light Plane)))

    ;; The tracer over `scene` and `environment` for a canvas of `format`,
    ;; its internal grid `width` by `height`, with texture layers of
    ;; `layer-size` and tone mapping by `tone`.
    (define (make-tracer (gpu Gpu) (scene Scene)
                         (environment Environment)
                         (format TextureFormat)
                         (width I32)
                         (height I32)
                         (layer-size I32)
                         (tone Tone))
      (→ Tracer)
      (let ((kit (make-kit gpu layer-size)))
        (tracer-over gpu kit (world-of gpu kit scene environment) format width height tone)))

    ;; A BVH for `scene` by the tracer's builder, for `retrace-built`, so a
    ;; caller can build it ahead of the frame that changes scenes.
    (define (build-scene-bvh (gpu Gpu) (tracer Tracer) (scene Scene)) (→ Bvh)
      (build-bvh gpu (● tracer kit builder) (scene-triangles scene)))

    (define (refit-tracer! (gpu Gpu) (tracer Tracer)) (→ Unit)
      (refit-bvh! gpu (● tracer world bvh)))

    (define (tracer-over (gpu Gpu) (kit Kit) (world World) (format TextureFormat) (width I32)
                         (height I32) (tone Tone)) (→ Tracer)
                         (let* ((targets (targets-for gpu width height (● world scene blended)))
                                (post (make-post gpu format width height tone)))
                           (new Tracer
                             (kit kit)
                             (world world)
                             (targets targets)
                             (bindings (bind gpu kit world targets))
                             (svgf (make-svgf gpu
                                              (svgf-inputs kit targets)
                                              (● post targets light-view)
                                              width
                                              height))
                             (blended-svgf (refiltered gpu kit (None) targets))
                             (post post) (upscale (None)) (photography (None))
                             (guiding (default-light-guiding))
                             (last (None))
                             (bounces 0)
                             (still 0)
                             (sky-revision -1) (frame 0))))

    (define (tracer-frames (tracer Tracer)) (→ I32) (● tracer still))

    (define (resize-tracer (gpu Gpu) (tracer Tracer) (width I32) (height I32)) (→ Tracer)
      (if (and (= width (● tracer targets width)) (= height (● tracer targets height)))
          tracer
          (begin
            (release-targets gpu (● tracer targets))
            (rebound gpu tracer
                     (● tracer world)
                     (targets-for gpu width height (● tracer world scene blended))
                     (resize-post gpu (● tracer post) width height) #t))))

    ;; The tracer drawing another scene in another environment with the
    ;; same pipelines and targets, but for a blended layer the new scene
    ;; needs or does not. The old scene's BVH is let go; the old scene and
    ;; environment are the caller's, as they were given.
    (define (retrace (gpu Gpu) (tracer Tracer) (scene Scene) (environment Environment))
      (→ Tracer)
      (retrace-built gpu tracer scene environment (build-scene-bvh gpu tracer scene)))

    ;; The new tree may be prepared while the previous neighbourhood draws.
    ;; Ownership transfers here. A scene cut invalidates history, but the same
    ;; render targets and filter allocations can hold the new first frame.
    (define (retrace-built (gpu Gpu)
                           (tracer Tracer)
                           (scene Scene)
                           (environment Environment)
                           (tree Bvh))
      (→ Tracer)
      (let* ((targets (● tracer targets))
             (resize (if (some-blended? targets) (not (● scene blended)) (● scene blended))))
        (release-bvh gpu (● tracer world bvh))
        (rebound gpu tracer (new World (scene scene) (bvh tree) (environment environment))
                 (if resize (begin (release-targets gpu targets)
                                   (targets-for gpu
                                                (● targets width)
                                                (● targets height)
                                                (● scene blended)))
                     targets)
                 (● tracer post) resize)))

    (define (some-blended? (targets Targets)) (→ Bool)
      (match (● targets blended)
        ((Some _) #t)
        ((None) #f)))

    ;; The tracer over another world or other targets: new bindings in
    ;; place of the old, the filters told of the planes, and a history
    ;; that starts again, from a camera that has not moved.
    (define (rebound (gpu Gpu)
                     (tracer Tracer)
                     (world World)
                     (targets Targets)
                     (post Post)
                     (resize Bool))
      (→ Tracer)
      (when (or resize (match (● tracer photography) ((Some _) #t) (_ #f)))
        (match (● tracer upscale) ((Some u) (release-upscaler gpu u)) (_ (unit))))
      (for-each (lambda (group) ((● gpu destroy) (BindGroupObject group)))
                (groups-of (● tracer bindings)))
      (new Tracer
        (kit (● tracer kit))
        (world world)
        (targets targets)
        (bindings (bind gpu (● tracer kit) world targets))
        (svgf (if resize (resize-svgf gpu (● tracer svgf)
                                      (svgf-inputs (● tracer kit) targets)
                                      (● post targets light-view)
                                      (● targets width)
                                      (● targets height)) (● tracer svgf)))
        (blended-svgf (if resize
                          (refiltered gpu (● tracer kit) (● tracer blended-svgf) targets)
                          (● tracer blended-svgf)))
        (post post)
        (upscale
         (match (● tracer photography) ((Some _) (None)) (_ (if resize (None) (● tracer upscale)))))
        (photography (match (● tracer photography)
                       ((Some p)
                        (release-photography gpu p)
                        (Some
                         (camera-effects gpu (● tracer kit) world targets post (● p settings))))
                       (_ (None))))
        (guiding (● tracer guiding))
        (last (None))
        (bounces (● tracer bounces))
        (still 0)
        (sky-revision -1) (frame (● tracer frame))))

    (define (world-of (gpu Gpu) (kit Kit) (scene Scene) (environment Environment)) (→ World)
      (new World
        (scene scene)
        (bvh (build-bvh gpu (● kit builder) (scene-triangles scene)))
        (environment environment)))

    (define (svgf-inputs (kit Kit) (targets Targets)) (→ SvgfInputs)
      (filtered kit (● targets planes) (● targets depth) (● targets noisy)))

    ;; The blended layer's filters over the targets' layer, with its own
    ;; motion and depth: made, resized, or let go of where there is none.
    (define (refiltered (gpu Gpu) (kit Kit) (old (Option Svgf)) (targets Targets)) (→ (Option Svgf))
      (match (● targets blended)
        ((Some b)
         (let ((inputs (filtered kit (● b planes) (● b depth) (● b noisy)))
               (light (● b light view))
               (width (● targets width))
               (height (● targets height)))
           (Some (match old
                   ((Some svgf) (resize-svgf gpu svgf inputs light width height))
                   ((None) (make-svgf gpu inputs light width height))))))
        ((None)
         (match old
           ((Some svgf) (release-svgf gpu svgf))
           ((None) (unit)))
         (None))))

    (define (filtered (kit Kit) (planes (List Plane)) (depth Plane) (noisy Plane)) (→ SvgfInputs)
      (new SvgfInputs
        (noisy (● noisy view))
        (triangles (● (list-ref planes 5) view))
        (material (● (list-ref planes 3) view))
        (normals (● (list-ref planes 0) view))
        (emission (● (list-ref planes 1) view))
        (albedo (● (list-ref planes 2) view))
        (motion (● (list-ref planes 4) view))
        (depth (● depth view))
        (camera (● kit camera))))

    ;; ---- Frames ----

    (record TraceSettings
      ((display-width I32)
       (display-height I32)))

    (define (same-output? (old (Option Upscaler)) (settings TraceSettings)) (→ Bool)
      (match old
        ((Some u) (and (= (● u width) (● settings display-width))
                       (= (● u height) (● settings display-height))))
        (_ #f)))

    ;; Color and depth history live on the stable display grid at every render scale.
    (define (display-output (gpu Gpu) (t Tracer) (settings TraceSettings)) (→ Upscaler)
      (let ((w (● settings display-width)) (h (● settings display-height)) (old (● t upscale)))
        (unless (and (> w 0) (> h 0)) (panic "display dimensions must be positive"))
        (match old
          ((Some u) (if (same-output? old settings) u
                        (begin (release-upscaler gpu u) (make-display gpu t w h))))
          (_ (make-display gpu t w h)))))

    (define (make-display (gpu Gpu) (t Tracer) (w I32) (h I32)) (→ Upscaler)
      (make-upscaler-from gpu (● t post) (● t kit camera) (● t targets depth)
                          (match (● t targets blended)
                            ((Some b) (● b depth))
                            (_ (● t targets depth)))
                          (● t targets planes) w h
                          (match (● t photography)
                            ((Some p) (● p output view))
                            (_ (● t post targets light-view)))))
    (define (camera-effects (gpu Gpu)
                            (kit Kit)
                            (world World)
                            (t Targets)
                            (post Post)
                            (s LensSettings))
      (→ Photography)
      (make-photography gpu (● kit camera) (● world bvh) (● world scene) (● world environment)
                        (● t depth view)
                        (match (● t blended) ((Some b) (● b depth view)) (_ (● t depth view)))
                        (● post targets light-view) (● t width) (● t height) s))
    (define (with-photography (gpu Gpu) (tracer Tracer) (s LensSettings)) (→ Tracer)
      (match (● tracer photography)
        ((Some p) (set! (● p settings) s) tracer)
        (_ (match (● tracer upscale) ((Some u) (release-upscaler gpu u)) (_ (unit)))
           (Tracer-photography-set (Tracer-upscale-set tracer (None))
                                   (Some (camera-effects gpu
                                                         (● tracer kit)
                                                         (● tracer world)
                                                         (● tracer targets)
                                                         (● tracer post)
                                                         s))))))

    (define (discard-trace-history (t Tracer)) (→ Tracer)
      (Tracer-last-set (Tracer-sky-revision-set t -1) (None)))

    ;; Rasterize once, trace every internal pixel, filter each layer and present.
    (define (draw-traced (gpu Gpu) (tracer Tracer) (canvas GpuTextureView)
                         (camera Camera3D) (spread F32) (exposure F32)
                         (bounces I64) (moved Bool) (settings TraceSettings))
      (→ Tracer)
      (draw-traced-samples gpu tracer canvas camera spread exposure bounces moved settings 1))

    (define (draw-traced-samples (gpu Gpu) (tracer Tracer) (canvas GpuTextureView)
                                 (camera Camera3D) (spread F32) (exposure F32)
                                 (bounces I64) (moved Bool) (settings TraceSettings) (samples I32))
      (→ Tracer)
      (unless (and (>= samples 1) (<= samples 4)) (panic "path samples outside 1 to 4"))
      (unless (and (>= bounces 1) (<= bounces most-bounces))
        (panic (string-append "bounces outside 1 to " (show most-bounces))))
      (let* ((rates (light-guiding-rates (● tracer guiding)))
             (out (display-output gpu tracer settings))
             (view-camera (after (● tracer last)
                                 (jitter-camera camera
                                                (sample-phase (● tracer frame))
                                                (● tracer targets width)
                                                (● tracer targets height))))
             (cut (or (match (● tracer last) ((None) #t) (_ #f))
                      (not (= bounces (● tracer bounces)))))
             (relit (not (= (● tracer sky-revision) (● tracer world environment revision))))
             (moving (or moved relit (not (same-camera? (● tracer last) camera))))
             (reuse (cond ((or cut relit) 0) (moving 2) (else 1)))
             (encoder ((● gpu create-command-encoder))))
        (write-path-inputs! gpu tracer view-camera spread samples reuse bounces rates)
        (draw-surfaces gpu encoder tracer)
        (trace-sample gpu encoder tracer bounces (= samples 1))
        (when (> samples 1) (extra-paths! gpu encoder tracer spread bounces samples))
        (let ((svgf (filter-svgf-frame gpu encoder (● tracer svgf) moving exposure cut))
              (blended-svgf (match (● tracer blended-svgf)
                              ((Some s)
                               (Some (filter-svgf-frame gpu encoder s moving exposure cut)))
                              (_ (None)))))
          (draw-composed gpu encoder tracer)
          (match (● tracer photography) ((Some p) (photograph! gpu encoder p exposure)) (_ (unit)))
          (let* ((valid (and (not cut) (same-output? (● tracer upscale) settings)
                             (match (● tracer last)
                               ((Some v) (= exposure (● v exposure)))
                               (_ #f))))
                 (display
                  (resolve-upscaled gpu encoder canvas out (● tracer post)
                                    (● tracer frame) valid moving)))
            ((● gpu submit) (list ((● gpu finish) encoder)))
            (new Tracer
              (kit (● tracer kit))
              (world (● tracer world))
              (targets (● tracer targets))
              (bindings (● tracer bindings))
              (svgf svgf)
              (blended-svgf blended-svgf)
              (post (● tracer post))
              (guiding (● tracer guiding))
              (upscale (Some display)) (photography (● tracer photography))
              (last (Some (new TracedView
                            (camera camera)
                            (raster view-camera)
                            (exposure exposure))))
              (bounces bounces)
              (still (if (or cut moving) 0 (+ (● tracer still) 1)))
              (sky-revision (● tracer world environment revision))
              (frame (+ (● tracer frame) 1)))))))

    ;; Rasterize and denoise once. Later paths use independent proposals and
    ;; share the ray queues. Only the first path updates next frame's reservoir.
    ;; Each copy reads a distinct prewritten slot when the encoder executes.
    (define (extra-paths! (gpu Gpu) (encoder GpuCommandEncoder) (t Tracer)
                          (spread F32) (bounces I64) (samples I32)) (→ Unit)
                          (let* ((kit (● t kit)) (slots (● kit sample-inputs))
                                 (stride-bytes (i64->i32 (stride tracing-shape)))
                                 (layer (* (● t targets width) (● t targets height)))
                                 (indices (map (lambda (n) (+ 1 (i64->i32 n)))
                                               (iota (- (i32->i64 samples) 1)))))
                            ((● gpu write-buffer) slots 0
                             (pack tracing-shape
                                   (concatenate
                                    (map (lambda (i) (list (tracing-of t spread 0 i samples -1)
                                                           (tracing-of t
                                                                       spread
                                                                       layer
                                                                       i
                                                                       samples
                                                                       -1)))
                                         indices))))
                            (for-each (lambda (i)
                                        (let ((at (* (* 2 (- i 1)) stride-bytes)))
                                          ((● gpu copy-buffer-to-buffer)
                                           encoder
                                           slots
                                           at
                                           (● kit tracing)
                                           0
                                           stride-bytes)
                                          ((● gpu copy-buffer-to-buffer)
                                           encoder
                                           slots
                                           (+ at stride-bytes)
                                           (● kit blended-tracing) 0 stride-bytes)
                                          (clear-counts gpu encoder kit)
                                          (trace-sample gpu encoder t bounces (= (+ i 1) samples))))
                                      indices)))

    ;; A full-resolution raw observation for a caller's encoder. Each seed
    ;; draws fresh proposals at every surface. The reference skips reservoir
    ;; reuse, SVGF and display passes. Submit before reusing the kit's uniforms.
    (define (encode-trace-observation (gpu Gpu) (encoder GpuCommandEncoder) (tracer Tracer)
                                      (camera Camera3D) (spread F32) (bounces I64) (seed I32))
      (→ Unit)
      (unless (and (>= bounces 1) (<= bounces most-bounces)) (panic "invalid observation depth"))
      (let ((t (Tracer-frame-set tracer seed)))
        (write-path-inputs! gpu t camera spread 1 -1 bounces (light-guiding-rates (● t guiding)))
        (draw-surfaces gpu encoder t)
        (trace-sample gpu encoder t bounces #t)))

    (define (write-path-inputs! (gpu Gpu) (tracer Tracer) (camera Camera3D) (spread F32)
                                (samples I32) (reuse I32) (bounces I64) (rates GuidingRates))
      (→ Unit)
      (let ((kit (● tracer kit)) (layer (* (● tracer targets width) (● tracer targets height))))
        ((● gpu write-buffer) (● kit camera) 0 (pod-bytes camera-shape camera))
        ((● gpu write-buffer) (● kit tracing) 0
         (pod-bytes tracing-shape (tracing-of tracer spread 0 0 samples reuse)))
        ((● gpu write-buffer) (● kit blended-tracing) 0
         (pod-bytes tracing-shape (tracing-of tracer spread layer 0 samples reuse)))
        ((● gpu write-buffer) (● kit wave) 0 (waves bounces rates))
        ((● gpu write-buffer) (● kit counts) 0 (zeros counts-size))))

    (define (clear-counts (gpu Gpu) (encoder GpuCommandEncoder) (kit Kit)) (→ Unit)
      ((● gpu copy-buffer-to-buffer)
       encoder
       (● kit cleared-counts)
       0
       (● kit counts)
       0
       (i64->i32 counts-size)))

    ;; A path from every pixel of each layer, the blended layer's after the
    ;; first hits' through the same bounded queues, each gathered into its
    ;; noisy plane.
    (define (trace-sample (gpu Gpu)
                          (encoder GpuCommandEncoder)
                          (tracer Tracer)
                          (bounces I64)
                          (last Bool))
      (→ Unit)
      (trace-paths gpu encoder tracer (● tracer bindings paths) bounces last)
      (match (● tracer bindings blended)
        ((Some groups) (clear-counts gpu encoder (● tracer kit))
         (trace-paths gpu encoder tracer (● groups paths) bounces last))
        ((None) (unit))))

    ;; The wavefront, in one compute pass: the first hits' paths, or the
    ;; blended layer's, as `primary` and `gather` read and write; then a
    ;; bounce at a time, each step over the queue the step before appended
    ;; to, then the radiance into the noisy plane. A step runs over its
    ;; longest possible queue, one ray per internal pixel.
    (define (trace-paths (gpu Gpu) (encoder GpuCommandEncoder)
                         (tracer Tracer)
                         (paths PathGroups) (bounces I64) (last Bool))
      (→ Unit)
      (let* ((pass ((● gpu begin-compute-pass) encoder))
             (steps (● tracer kit steps))
             (rays (● tracer kit rays))
             (bound (● tracer bindings))
             (targets (● tracer targets))
             (width (● targets width)) (height (● targets height))
             (capacity (* (i32->i64 width) (i32->i64 height))))
        ((● gpu set-compute-bind-group) pass 1 (● bound temporal-scene))
        ((● gpu set-compute-bind-group) pass 2 (● bound temporal-environment))
        (over-screen gpu pass width height (● steps temporal) (● paths temporal))
        ((● gpu set-compute-bind-group) pass 1 (● bound primary-scene))
        ((● gpu set-compute-bind-group) pass 2 (● bound primary-environment))
        (over-screen gpu pass width height (● steps primary) (● paths primary))
        (for-each (lambda (bounce)
                    (trace-rays gpu pass
                                (● rays occlude)
                                (● bounce occlude)
                                (Some (● bound occlude-cutout))
                                capacity)
                    ((● gpu set-compute-bind-group) pass 1 (● paths visibility))
                    (over-queue gpu pass (● steps connect) (● bounce connect) capacity)
                    (trace-rays gpu pass
                                (● rays intersect)
                                (● bounce intersect)
                                (Some (● bound intersect-cutout))
                                capacity)
                    ((● gpu set-compute-bind-group) pass 1 (● bound shade-scene))
                    ((● gpu set-compute-bind-group) pass 2 (● bound shade-environment))
                    (over-queue gpu pass (● steps shade) (● bounce shade) capacity))
                  (take (● bound bounces) bounces))
        (when last (over-screen gpu pass width height (● steps gather) (● paths gather)))
        ((● gpu end-compute-pass) pass)))

    (define (over-screen (gpu Gpu) (pass GpuComputePass)
                         (width I32) (height I32)
                         (kernel GpuComputePipeline)
                         (group GpuBindGroup))
      (→ Unit)
      ((● gpu set-compute-pipeline) pass kernel)
      ((● gpu set-compute-bind-group) pass 0 group)
      (dispatch-texels gpu pass width height))

    (define (over-queue (gpu Gpu) (pass GpuComputePass)
                        (kernel GpuComputePipeline)
                        (group GpuBindGroup)
                        (capacity I64))
      (→ Unit)
      ((● gpu set-compute-pipeline) pass kernel)
      ((● gpu set-compute-bind-group) pass 0 group)
      (dispatch-items gpu pass capacity 64))

    ;; The camera with the last frame's view-projection as its previous.
    (define (after (last (Option TracedView)) (camera Camera3D)) (→ Camera3D)
      (match last
        ((Some last)
         (new Camera3D
           (view-projection (● camera view-projection))
           (inverse (● camera inverse))
           (eye (● camera eye))
           (forward (● camera forward))
           (previous (● last raster view-projection))
           (previous-motion (● camera previous-motion))
           (scene-time (● camera scene-time))
           (previous-heading
            (new Vec2f (x (● last camera forward x)) (y (● last camera forward z))))))
        ((None) camera)))

    (define (same-camera? (last (Option TracedView)) (camera Camera3D)) (→ Bool)
      (match last
        ((Some last)
         (let ((before (pod-bytes camera-shape (● last camera)))
               (now (pod-bytes camera-shape camera)))
           (every? (lambda (index) (= (array-ref before index) (array-ref now index)))
                   (iota (array-length now)))))
        ((None) #f)))

    (define (tracing-of (tracer Tracer)
                        (spread F32)
                        (start I32)
                        (index I32)
                        (samples I32)
                        (reuse I32))
      (→ Tracing)
      (new Tracing
        (spread spread)
        (layer-size (i32->f32 (● tracer kit layer-size)))
        (sample-index index) (sample-weight (/ 1.0 (i32->f32 samples)))
        (frame (● tracer frame))
        (layer-offset start)
        (reuse reuse)))

    ;; A run of the scene's triangles, drawn with a pipeline and its group.
    (record SurfaceDraw
      ((pipeline GpuRenderPipeline)
       (group GpuBindGroup)
       (run SurfaceRun)))

    ;; The draws of the runs of one alpha mode.
    (define (runs-drawn (tracer Tracer)
                        (alpha I64)
                        (pipeline GpuRenderPipeline)
                        (group GpuBindGroup))
      (→ (List SurfaceDraw))
      (map (lambda (run) (new SurfaceDraw (pipeline pipeline) (group group) (run run)))
           (filter (lambda (run) (and (= (● run alpha) alpha) (> (● run count) 0)))
                   (● tracer world scene runs))))

    ;; The first hits: the opaque runs first, with nothing that discards, so
    ;; the depth test runs before their shader; then the masked runs. Then,
    ;; where the scene has the blended layer, its blended runs over a copy
    ;; of the first hits' depth, so that the depth test keeps the nearest
    ;; blended surface in front of them.
    (define (draw-surfaces (gpu Gpu) (encoder GpuCommandEncoder) (tracer Tracer)) (→ Unit)
      (let ((targets (● tracer targets)) (kit (● tracer kit)) (bound (● tracer bindings)))
        (surfaces-pass gpu encoder
                       (● targets planes)
                       (● targets depth)
                       (ClearDepth 1.0)
                       (append (runs-drawn tracer 0 (● kit opaque-surface) (● bound opaque-surface))
                               (runs-drawn tracer 1 (● kit surface) (● bound surface))))
        (match (pair-of (● targets blended) (● bound blended))
          ((Some (Pair b groups))
           ((● gpu copy-texture-to-texture) encoder
            (whole-texture (● targets depth texture))
            (whole-texture (● b depth texture))
            (● targets width)
            (● targets height))
           (surfaces-pass gpu encoder
                          (● b planes)
                          (● b depth)
                          (KeepDepth)
                          (runs-drawn tracer 2 (● kit blended-surface) (● groups surface))))
          ((None) (unit)))))

    ;; Both, when both are there.
    (define (pair-of (a (Option A)) (b (Option B))) (→ (Option (Pair A B))) (∀ (A B))
      (match a
        ((Some x)
         (match b
           ((Some y) (Some (new Pair (first x) (second y))))
           ((None) (None))))
        ((None) (None))))

    ;; One render pass into the planes and depth, of each run's three
    ;; corners a triangle, from its first triangle's.
    (define (surfaces-pass (gpu Gpu) (encoder GpuCommandEncoder)
                           (planes (List Plane))
                           (depth Plane)
                           (depth-load DepthLoad)
                           (draws (List SurfaceDraw)))
      (→ Unit)
      (let* ((clear (Clear (new Color (red 0.0) (green 0.0) (blue 0.0) (alpha 0.0))))
             (pass ((● gpu begin-render-pass) encoder
                    (new RenderPassDescriptor
                      (colors (map (lambda (plane)
                                     (Some (new ColorAttachment
                                             (view (● plane view))
                                             (load clear)
                                             (store #t))))
                                   planes))
                      (depth (Some (new DepthAttachment
                                     (view (● depth view))
                                     (load depth-load)
                                     (store #t))))))))
        (for-each (lambda (d)
                    ((● gpu set-pipeline) pass (● d pipeline))
                    ((● gpu set-bind-group) pass 0 (● d group))
                    ((● gpu draw) pass
                     (i64->i32 (* 3 (● d run count)))
                     1
                     (i64->i32 (* 3 (● d run first)))
                     0))
                  draws)
        ((● gpu end-pass) pass)))

    ;; The blended layer's light over the first hits', in the light they
    ;; were filtered into, by the layer's alpha, where the scene has it.
    (define (draw-composed (gpu Gpu) (encoder GpuCommandEncoder) (tracer Tracer)) (→ Unit)
      (match (● tracer bindings blended)
        ((Some groups)
         (let ((pass ((● gpu begin-render-pass) encoder
                      (new RenderPassDescriptor
                        (colors (list (Some (new ColorAttachment
                                              (view (● tracer post targets light-view))
                                              (load (Keep))
                                              (store #t)))))
                        (depth (None))))))
           ((● gpu set-pipeline) pass (● tracer kit compose))
           ((● gpu set-bind-group) pass 0 (● groups compose))
           ((● gpu draw) pass 3 1 0 0)
           ((● gpu end-pass) pass)))
        ((None) (unit))))

    ;; ---- Queues ----

    ;; A queue's count is a word alone in a slot of the counts, so a query
    ;; can bind it: bounce b's rays' in slot b, its shadow rays' in slot
    ;; most-bounces + b. The counts are zeroed each frame, and each is
    ;; appended to in one bounce only.
    (define (rays-word (bounce I64)) (→ I64) (* (quotient slot 4) bounce))
    (define (shadows-word (bounce I64)) (→ I64) (* (quotient slot 4) (+ most-bounces bounce)))

    (define counts-size (→ I64) (* slot (* 2 most-bounces)))

    (define (count-at (word I64)) (→ I32) (i64->i32 (* 4 word)))

    ;; Slot b of the wave for bounce b's steps: primary's at 0, shade's at
    ;; the bounce its rays leave from, the last, `bounces`, only adding
    ;; what they hit.
    (define (wave-of (bounce I64) (bounces I64) (guiding GuidingRates)) (→ Wave)
      (new Wave
        (guiding guiding)
        (step (new Vec4i (x (i64->i32 bounce)) (y (if (= bounce bounces) 1 0)) (z 0) (w 0)))
        (slots (new Vec4i
                 (x (i64->i32 (rays-word (max 0 (- bounce 1)))))
                 (y (i64->i32 (rays-word (min bounce (- most-bounces 1)))))
                 (z (i64->i32 (shadows-word (min bounce (- most-bounces 1)))))
                 (w 0)))))

    ;; Every slot of the wave for a frame of `bounces`.
    (define (waves (bounces I64) (guiding GuidingRates)) (→ Bytes)
      (uniform-slots wave-shape
                     (map (lambda (b) (wave-of b bounces guiding)) (iota (+ most-bounces 1)))))

    ;; ---- Targets ----

    ;; Normals, emission, albedo, material, motion and triangle, as
    ;; surface.wgsl.scm writes them.
    (define planes-formats
      (→ (List TextureFormat))
      (list (Rg16Float) (Rgba16Float) (Rgba8UnormSrgb) (Rgba8Unorm) (Rg16Float) (R32Uint)))

    ;; The targets for a size, with the blended layer's own where
    ;; `blended`, and room in the radiance for its paths.
    (define (targets-for (gpu Gpu) (width I32) (height I32) (blended Bool)) (→ Targets)
      (let ((width (max 1 width))
            (height (max 1 height))
            (drawn (list (RenderAttachment) (TextureBinding) (TextureCopySrc))))
        (let ((rays (* ray-size (* (i32->i64 width) (i32->i64 height)))))
          (new Targets
            (width width)
            (height height)
            (planes
             (map (lambda (format) (make-plane gpu "trace/gbuffer" width height format drawn))
                  planes-formats))
            (depth (make-plane gpu
                               "trace/depth"
                               width
                               height
                               (Depth32Float)
                               drawn))
            (noisy (make-plane gpu "trace/noisy"
                               width
                               height
                               (Rgba16Float)
                               (list (StorageBinding) (TextureBinding))))
            (blended (if blended (Some (blended-for gpu width height drawn)) (None)))
            (temporal (reservoir-buffer gpu "restir/temporal" width height))
            (history (reservoir-buffer gpu "restir/history" width height))
            (queues (map (lambda (index) (storage-buffer gpu "trace/rays" rays (Nil))) (iota 2)))
            (shadows (storage-buffer gpu "trace/shadows" rays (Nil)))
            (radiance (storage-buffer gpu "trace/radiance"
                                      (* (if blended 2 1)
                                         (* 16 (* (i32->i64 width) (i32->i64 height))))
                                      (list (CopySrc))))))))

    (define (blended-for (gpu Gpu) (width I32) (height I32) (drawn (List TextureUsage))) (→ Blended)
      (new Blended
        (planes (map (lambda (format) (make-plane gpu "trace/blended" width height format drawn))
                     planes-formats))
        (depth (make-plane gpu
                           "trace/blended-depth"
                           width
                           height
                           (Depth32Float)
                           (Cons (TextureCopyDst) drawn)))
        (noisy (make-plane gpu "trace/blended-noisy"
                           width
                           height
                           (Rgba16Float)
                           (list (StorageBinding) (TextureBinding))))
        (history (reservoir-buffer gpu "restir/blended-history" width height))
        (light (make-plane gpu "trace/blended-light"
                           width
                           height
                           light-format
                           (list (StorageBinding) (TextureBinding))))))

    ;; Every field's object, each named here.
    (define (release-targets (gpu Gpu) (targets Targets)) (→ Unit)
      (for-each (lambda (buffer) ((● gpu destroy) (BufferObject buffer)))
                (append (append (● targets queues)
                                (list (● targets shadows) (● targets radiance)
                                      (● targets temporal) (● targets history)))
                        (match (● targets blended)
                          ((Some b) (list (● b history)))
                          ((None) (Nil)))))
      (for-each (lambda (plane) (release-plane gpu plane))
                (append (list (● targets depth) (● targets noisy))
                        (append (● targets planes)
                                (match (● targets blended)
                                  ((Some b)
                                   (append (list (● b depth) (● b noisy) (● b light)) (● b planes)))
                                  ((None) (Nil)))))))

    ;; ---- Bindings ----

    ;; Every bind group: the G-buffer's draw; `primary`, the triangles it
    ;; places first hits on and the environment it reads; each bounce's;
    ;; `gather`; the blended layer's, where the scene has it; and what the
    ;; queries and `shade` read of the scene and the environment, which
    ;; are the same for every bounce of either layer.
    (record Bindings
      ((opaque-surface GpuBindGroup)
       (surface GpuBindGroup)
       (paths PathGroups)
       (temporal-scene GpuBindGroup)
       (primary-scene GpuBindGroup)
       (temporal-environment GpuBindGroup)
       (primary-environment GpuBindGroup)
       (bounces (List Bounce))
       (blended (Option BlendedGroups))
       (occlude-cutout GpuBindGroup)
       (intersect-cutout GpuBindGroup)
       (shade-scene GpuBindGroup)
       (shade-environment GpuBindGroup)))

    ;; The blended layer's draw, its `primary` and `gather` over its own
    ;; planes, and its composing over the first hits' light.
    (record BlendedGroups
      ((surface GpuBindGroup)
       (paths PathGroups)
       (compose GpuBindGroup)))

    (record PathGroups
      ((temporal GpuBindGroup)
       (primary GpuBindGroup)
       (visibility GpuBindGroup)
       (gather GpuBindGroup)))

    ;; A bounce's groups: its shadow rays' query, `connect` over what it
    ;; found, its rays' query, and `shade` over what they hit. Bounce b's
    ;; rays are in queue b mod 2, and `shade` appends the next bounce's to
    ;; the other, so a frame only walks the bounces in order.
    (record Bounce
      ((occlude GpuBindGroup)
       (connect GpuBindGroup)
       (intersect GpuBindGroup)
       (shade GpuBindGroup)))

    (define (bind (gpu Gpu) (kit Kit) (world World) (targets Targets)) (→ Bindings)
      (let ((steps (● kit steps)) (rays (● kit rays)) (scene (● world scene)))
        (new Bindings
          (opaque-surface (surface-group gpu (● kit opaque-surface) kit scene))
          (surface (surface-group gpu (● kit surface) kit scene))
          (paths (path-groups gpu kit (● kit tracing) targets (● targets planes) (● targets depth)
                              (● targets noisy) (● targets history)))
          (temporal-scene (triangle-group gpu (● steps temporal) scene #f))
          (primary-scene (triangle-group gpu (● steps primary) scene #t))
          (temporal-environment (environment-group gpu (● steps temporal) (● world environment)))
          (primary-environment (environment-group gpu (● steps primary) (● world environment)))
          (bounces (map (lambda (bounce) (bounce-groups gpu kit (● world bvh) targets bounce))
                        (iota most-bounces)))
          (blended (match (● targets blended)
                     ((Some b) (Some (blended-groups gpu kit scene targets b)))
                     ((None) (None))))
          (occlude-cutout (scene-group gpu (● rays occlude) scene #f))
          (intersect-cutout (scene-group gpu (● rays intersect) scene #f))
          (shade-scene (scene-group gpu (● steps shade) scene #t))
          (shade-environment (environment-group gpu (● steps shade) (● world environment))))))

    (define (blended-groups (gpu Gpu) (kit Kit) (scene Scene) (targets Targets) (b Blended))
      (→ BlendedGroups)
      (new BlendedGroups
        (surface (surface-group gpu (● kit blended-surface) kit scene))
        (paths (path-groups gpu kit (● kit blended-tracing) targets (● b planes) (● b depth)
                            (● b noisy) (● b history)))
        (compose ((● gpu create-bind-group)
                  (new BindGroupDescriptor
                    (label "trace/compose")
                    (pipeline (RenderPipeline (● kit compose)))
                    (group 0)
                    (entries (list (TextureEntry 0 (● b light view))
                                   (TextureEntry 1 (● (list-ref (● b planes) 2) view)))))))))

    (define (groups-of (bound Bindings)) (→ (List GpuBindGroup))
      (concatenate (list (list (● bound opaque-surface)
                               (● bound surface)
                               (● bound temporal-scene)
                               (● bound primary-scene)
                               (● bound temporal-environment)
                               (● bound primary-environment)
                               (● bound occlude-cutout)
                               (● bound intersect-cutout)
                               (● bound shade-scene)
                               (● bound shade-environment))
                         (path-group-list (● bound paths))
                         (match (● bound blended)
                           ((Some g)
                            (append (list (● g surface) (● g compose))
                                    (path-group-list (● g paths))))
                           ((None) (Nil)))
                         (concatenate (map (lambda (bounce)
                                             (list (● bounce occlude)
                                                   (● bounce connect)
                                                   (● bounce intersect)
                                                   (● bounce shade)))
                                           (● bound bounces))))))

    (define (path-group-list (paths PathGroups)) (→ (List GpuBindGroup))
      (list (● paths temporal) (● paths primary) (● paths visibility) (● paths gather)))

    ;; Each layer has its own history. The first dispatch finishes reading it
    ;; before primary writes it back; both layers take turns using scratch.
    (define (path-groups (gpu Gpu) (kit Kit) (tracing GpuBuffer) (targets Targets)
                         (planes (List Plane)) (depth Plane) (noisy Plane) (history GpuBuffer))
      (→ PathGroups)
      (let ((scratch (● targets temporal))
            (surface (list (BufferEntry 0 (● kit camera) 0 0)
                           (BufferEntry 1 tracing 0 0)
                           (slot-entry 2 (● kit wave) 0)
                           (TextureEntry 8 (● (list-ref planes 5) view))
                           (TextureEntry 9 (● (list-ref planes 0) view))
                           (TextureEntry 10 (● (list-ref planes 1) view))
                           (TextureEntry 11 (● (list-ref planes 2) view))
                           (TextureEntry 12 (● (list-ref planes 3) view))
                           (TextureEntry 13 (● depth view)))))
        (new PathGroups
          (temporal (step-group gpu (● kit steps temporal)
                                (append surface (list (BufferEntry 15 history 0 0)
                                                      (BufferEntry 16 scratch 0 0)
                                                      (TextureEntry 17
                                                                    (● (list-ref planes 4)
                                                                       view))))))
          (primary (step-group gpu (● kit steps primary)
                               (append surface
                                       (list (BufferEntry 4 (list-ref (● targets queues) 0) 0 0)
                                             (BufferEntry 5 (● targets shadows) 0 0)
                                             (BufferEntry 6 (● kit counts) 0 0)
                                             (BufferEntry 7 (● targets radiance) 0 0)
                                             (BufferEntry 15 scratch 0 0)
                                             (BufferEntry 16 history 0 0)))))
          (visibility (kernel-group gpu (● kit steps connect) 1 "restir/visibility"
                                    (list (BufferEntry 8 history 0 0))))
          (gather (gather-group gpu kit tracing targets depth noisy)))))

    ;; `gather` of a wave's radiance into its noisy plane.
    (define (gather-group (gpu Gpu) (kit Kit) (tracing GpuBuffer)
                          (targets Targets)
                          (depth Plane)
                          (noisy Plane))
      (→ GpuBindGroup)
      (step-group gpu (● kit steps gather)
                  (list (BufferEntry 1 tracing 0 0)
                        (BufferEntry 7 (● targets radiance) 0 0)
                        (TextureEntry 13 (● depth view))
                        (TextureEntry 14 (● noisy view)))))

    ;; `shade` binds all eight storage buffers a kernel may: the two
    ;; queues, the shadow rays, the counts and the radiance here, and the
    ;; scene's vertices, indices and materials in its group 1. So the
    ;; counts are one buffer, which a step indexes by its wave's words and
    ;; a query binds a slot of.
    (define (bounce-groups (gpu Gpu) (kit Kit) (bvh Bvh) (targets Targets) (bounce I64))
      (→ Bounce)
      (let* ((steps (● kit steps))
             (counts (● kit counts))
             (shadows (● targets shadows))
             (from (list-ref (● targets queues) (remainder bounce 2)))
             (to (list-ref (● targets queues) (remainder (+ bounce 1) 2)))
             (tallies (list (BufferEntry 5 shadows 0 0)
                            (BufferEntry 6 counts 0 0)
                            (BufferEntry 7 (● targets radiance) 0 0))))
        (new Bounce
          (occlude
           (ray-group gpu
                      (● kit rays occlude)
                      bvh
                      shadows
                      counts
                      (count-at (shadows-word bounce))))
          (connect
           (step-group gpu (● steps connect) (Cons (slot-entry 2 (● kit wave) bounce) tallies)))
          (intersect
           (ray-group gpu (● kit rays intersect) bvh from counts (count-at (rays-word bounce))))
          (shade (step-group gpu (● steps shade)
                             (append (list (BufferEntry 0 (● kit camera) 0 0)
                                           (BufferEntry 1 (● kit tracing) 0 0)
                                           (slot-entry 2 (● kit wave) (+ bounce 1))
                                           (BufferEntry 3 from 0 0)
                                           (BufferEntry 4 to 0 0))
                                     tallies))))))

    (define (step-group (gpu Gpu) (kernel GpuComputePipeline) (entries (List BindGroupEntry)))
      (→ GpuBindGroup)
      (kernel-group gpu kernel 0 "trace/step" entries))

    ;; Both first-hit kernels project depth onto the rasterized triangle.
    (define (light-entry (scene Scene) (lit Bool)) (→ (List BindGroupEntry))
      (if lit (list (TextureEntry 5 (● scene lights plane view))) (Nil)))
    (define (emitter-entries (scene Scene)) (→ (List BindGroupEntry))
      (list (TextureEntry 6 (● scene emitters triangles view))
            (TextureEntry 7 (● scene emitters distribution view))))
    (define (triangle-group (gpu Gpu) (kernel GpuComputePipeline) (scene Scene) (lit Bool))
      (→ GpuBindGroup)
      (kernel-group gpu kernel 1 "trace/triangles"
                    (append (emitter-entries scene)
                            (append (light-entry scene lit)
                                    (list (BufferEntry 0 (● scene vertices) 0 0)
                                          (BufferEntry 1 (● scene indices) 0 0))))))

    ;; Group 1 of a kernel that reads the scene (scene.wgsl.scm).
    (define (scene-group (gpu Gpu) (kernel GpuComputePipeline) (scene Scene) (lit Bool))
      (→ GpuBindGroup)
      (kernel-group gpu kernel
                    1
                    "trace/scene"
                    (append (if lit (append (emitter-entries scene) (light-entry scene #t)) (Nil))
                            (list (BufferEntry 0 (● scene vertices) 0 0)
                                  (BufferEntry 1 (● scene indices) 0 0)
                                  (BufferEntry 2 (● scene materials) 0 0)
                                  (TextureEntry 3 (● scene layers-view))
                                  (SamplerEntry 4 (● scene sampler))))))

    (define (surface-group (gpu Gpu) (pipeline GpuRenderPipeline) (kit Kit) (scene Scene))
      (→ GpuBindGroup)
      ((● gpu create-bind-group) (new BindGroupDescriptor
                                   (label "trace/surface")
                                   (pipeline (RenderPipeline pipeline))
                                   (group 0)
                                   (entries (list (BufferEntry 0 (● kit camera) 0 0)
                                                  (BufferEntry 1 (● scene vertices) 0 0)
                                                  (BufferEntry 2 (● scene materials) 0 0)
                                                  (TextureEntry 3 (● scene layers-view))
                                                  (SamplerEntry 4 (● scene sampler))
                                                  (BufferEntry 5 (● scene indices) 0 0))))))

    ;; ---- The kit ----

    (define (make-kit (gpu Gpu) (layer-size I32)) (→ Kit)
      (new Kit
        (opaque-surface (surface-pipeline gpu "opaque_fragment"))
        (surface (surface-pipeline gpu "surface_fragment"))
        (blended-surface (surface-pipeline gpu "blended_fragment"))
        (compose (compose-pipeline gpu))
        (steps (path-steps gpu))
        (rays (make-ray-kernels gpu (string-append (declarations material-shape) scene-shader)))
        (builder (make-bvh-builder gpu))
        (camera (uniform-buffer gpu "trace/camera" (zeros (stride camera-shape))))
        (tracing (uniform-buffer gpu "trace/tracing" (zeros (stride tracing-shape))))
        (blended-tracing
         (uniform-buffer gpu "trace/blended-tracing" (zeros (stride tracing-shape))))
        (wave (uniform-buffer gpu "trace/wave"
                              (waves most-bounces
                                     (light-guiding-rates (default-light-guiding)))))
        (counts (storage-buffer gpu "trace/counts" counts-size (list (CopyDst))))
        (sample-inputs (storage-buffer gpu
                                       "trace/sample-inputs"
                                       (* 6 (stride tracing-shape))
                                       (list (CopySrc) (CopyDst))))
        (cleared-counts (storage-buffer gpu "trace/cleared-counts" counts-size (list (CopySrc))))
        (layer-size layer-size)))

    (define (zeros (count I64)) (→ Bytes) (make-array count (i32->u8 0)))

    (define (path-steps (gpu Gpu)) (→ Steps)
      (let ((module ((● gpu create-shader-module)
                     (new ShaderModuleDescriptor
                       (label "trace/path")
                       (code (string-append (declarations camera-shape)
                                            (declarations tracing-shape)
                                            (declarations wave-shape)
                                            (declarations material-shape)
                                            scene-shader
                                            environment-light-shader
                                            reservoir-shader
                                            emitter-light-shader
                                            restir-shader
                                            water-shader
                                            path-shader))))))
        (new Steps
          (temporal (compute-kernel gpu module "restir" "temporal_reservoirs"))
          (primary (compute-kernel gpu module "trace" "primary"))
          (connect (compute-kernel gpu module "trace" "connect"))
          (shade (compute-kernel gpu module "trace" "shade"))
          (gather (compute-kernel gpu module "trace" "gather")))))

    ;; The surfaces' draw, `surface_fragment` for the first hits' and
    ;; `blended_fragment` for the blended layer's.
    (define (surface-pipeline (gpu Gpu) (entry String)) (→ GpuRenderPipeline)
      ((● gpu create-render-pipeline)
       (new RenderPipelineDescriptor
         (label (string-append "trace/" entry))
         (module ((● gpu create-shader-module) (new ShaderModuleDescriptor
                                                 (label "trace/surface")
                                                 (code
                                                  (string-append
                                                   (declarations camera-shape)
                                                   (declarations material-shape)
                                                   water-shader
                                                   surface-shader)))))
         (vertex-entry "surface_vertex")
         (buffers (Nil))
         (fragment (Some (new FragmentState
                           (entry entry)
                           (targets (map (lambda (format)
                                           (Some (new ColorTarget
                                                   (format format)
                                                   (blend (None)))))
                                         planes-formats)))))
         (topology (TriangleList))
         (cull (CullNone))
         (depth
          (Some (new DepthState
                  (format (Depth32Float))
                  (write #t)
                  (compare (CompareLess))))))))

    ;; One triangle over the screen, blending the layer's light over what
    ;; the light target holds.
    (define (compose-pipeline (gpu Gpu)) (→ GpuRenderPipeline)
      ((● gpu create-render-pipeline)
       (new RenderPipelineDescriptor
         (label "trace/compose")
         (module ((● gpu create-shader-module)
                  (new ShaderModuleDescriptor (label "trace/compose") (code compose-shader))))
         (vertex-entry "compose_vertex")
         (buffers (Nil))
         (fragment (Some (new FragmentState
                           (entry "compose_fragment")
                           (targets (list (Some (new ColorTarget
                                                  (format light-format)
                                                  (blend (Some over)))))))))
         (topology (TriangleList))
         (cull (CullNone))
         (depth (None)))))

    ))
