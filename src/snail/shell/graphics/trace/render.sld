;; A scene path traced to the canvas, a frame at a time, composed of the
;; graphics middleware:
;;
;;   surfaces   the first hits, rasterized into a G-buffer, and the
;;              nearest blended surface in front of them into a second,
;;              the blended layer (surface.wgsl.scm)
;;   direct     biased first-hit environment sampling (trace/restir.wgsl.scm)
;;              with the accumulators of (snail shell graphics restir)
;;   paths      a wavefront of kernels (path.wgsl.scm), each bounce's rays
;;              traced by (snail shell graphics bvh)'s queries with the
;;              scene's cutouts (scene.wgsl.scm), lit by an environment
;;              of (snail shell graphics environment)
;;   filters    (snail shell graphics svgf) over the paths and the G-buffer,
;;              for each layer
;;   compose    the blended layer's light over the first hits', by its
;;              alpha (compose.wgsl.scm)
;;   post       (snail shell graphics passes)'s tone mapping and FXAA
;;
;; A `Tracer` is made once for a scene and the canvas, and resized with it:
;;
;;   (let ((sized (resize-tracer gpu tracer w h)))
;;     (draw-traced gpu sized canvas camera spread exposure 4))
;;
;; Each frame says how many bounces its paths make, up to `most-bounces`.
(define-library (snail shell graphics trace render)
  (export
   Tracer
   most-bounces
   TraceSampling
   EveryPixel
   Checkerboard
   draw-sampled-traced
   make-tracer
   make-moving-tracer
   make-graded-moving-tracer
   discard-trace-history
   refit-tracer!
   draw-moving-traced
   resize-tracer
   retrace
   draw-traced
   tracer-frames)
  (import
   (snail core base)
   (snail shell gpu)
   (snail shell graphics pod)
   (snail shell graphics kernel)
   (snail shell graphics raster)
   (snail shell graphics passes)
   (snail shell graphics bvh)
   (snail shell graphics restir)
   (snail shell graphics svgf)
   (snail shell graphics environment)
   (only (snail shell graphics shaders) environment-light-shader)
   (snail shell graphics trace scene)
   (snail shell graphics trace shaders))
  (begin

    ;; ---- Uniforms ----

    ;; view holds the camera's spread in radians a pixel and the layers' size.
    ;; frame holds the frame number, radiance offset, and whether the previous
    ;; draw left reservoir history for this world and size. Its last word
    ;; enables the checkerboard on a still frame.
    (record Tracing
      ((view Vec4f)
       (frame Vec4i))
      (deriving Pod))

    ;; A bounce's uniform, one slot each: its number and whether it is the
    ;; last; then the words of the counts it reads and appends to
    ;; (path.wgsl.scm).
    (record Wave
      ((step Vec4i)
       (slots Vec4i))
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
       (last (Option Camera3D))
       (bounces I64)
       (still I32)
       (frame I32)
       (sky-revision I64)))

    ;; What is made once: the pipelines, the uniforms, the queues' counts,
    ;; and zeros to clear them with between the first hits' paths and the
    ;; blended layer's, whose `tracing` puts its radiance past theirs.
    (record Kit
      ((surface GpuRenderPipeline)
       (blended-surface GpuRenderPipeline)
       (compose GpuRenderPipeline)
       (steps Steps)
       (rays RayKernels)
       (camera GpuBuffer)
       (tracing GpuBuffer)
       (blended-tracing GpuBuffer)
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
    ;; caller's, and the scene's BVH, which is the tracer's.
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

    (define (make-tracer (gpu Gpu) (scene Scene)
                         (environment Environment)
                         (format TextureFormat)
                         (width I32)
                         (height I32)
                         (layer-size I32))
      (→ Tracer)
      (tracer-over gpu (world-of gpu scene environment #f) format width height layer-size (Filmic)))

    (define (make-moving-tracer (gpu Gpu) (scene Scene) (environment Environment)
                                (format TextureFormat)
                                (width I32)
                                (height I32)
                                (layer-size I32))
      (→ Tracer)
      (make-graded-moving-tracer gpu scene environment format width height layer-size (Filmic)))

    (define (make-graded-moving-tracer (gpu Gpu) (scene Scene) (environment Environment)
                                       (format TextureFormat) (width I32) (height I32)
                                       (layer-size I32) (tone Tone))
      (→ Tracer)
      (tracer-over gpu (world-of gpu scene environment #t) format width height layer-size tone))

    (define (refit-tracer! (gpu Gpu) (tracer Tracer)) (→ Unit)
      (refit-bvh! gpu (● tracer world bvh)))

    (define (tracer-over (gpu Gpu) (world World) (format TextureFormat) (width I32) (height I32)
                         (layer-size I32) (tone Tone)) (→ Tracer)
                         (let* ((kit (make-kit gpu layer-size))
                                (targets (targets-for gpu width height (● world scene blended)))
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
                             (post post)
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
                     (resize-post gpu (● tracer post) width height)))))

    ;; The tracer drawing another scene in another environment with the
    ;; same pipelines and targets, but for a blended layer the new scene
    ;; needs or does not. The old scene's BVH is let go; the old scene and
    ;; environment are the caller's, as they were given.
    (define (retrace (gpu Gpu) (tracer Tracer) (scene Scene) (environment Environment))
      (→ Tracer)
      (let ((moving (match (● tracer world bvh refitter) ((Some _) #t) (_ #f)))
            (targets (● tracer targets)))
        (release-bvh gpu (● tracer world bvh))
        (rebound gpu
                 tracer
                 (world-of gpu scene environment moving)
                 (if (if (some-blended? targets) (● scene blended) (not (● scene blended)))
                     targets
                     (begin
                       (release-targets gpu targets)
                       (targets-for gpu (● targets width) (● targets height) (● scene blended))))
                 (● tracer post))))

    (define (some-blended? (targets Targets)) (→ Bool)
      (match (● targets blended)
        ((Some _) #t)
        ((None) #f)))

    ;; The tracer over another world or other targets: new bindings in
    ;; place of the old, the filters told of the planes, and a history
    ;; that starts again, from a camera that has not moved.
    (define (rebound (gpu Gpu) (tracer Tracer) (world World) (targets Targets) (post Post))
      (→ Tracer)
      (for-each (lambda (group) ((● gpu destroy) (BindGroupObject group)))
                (groups-of (● tracer bindings)))
      (new Tracer
        (kit (● tracer kit))
        (world world)
        (targets targets)
        (bindings (bind gpu (● tracer kit) world targets))
        (svgf (resize-svgf gpu (● tracer svgf)
                           (svgf-inputs (● tracer kit) targets)
                           (● post targets light-view)
                           (● targets width)
                           (● targets height)))
        (blended-svgf (refiltered gpu (● tracer kit) (● tracer blended-svgf) targets))
        (post post)
        (last (None))
        (bounces (● tracer bounces))
        (still 0)
        (sky-revision -1) (frame (● tracer frame))))

    (define (world-of (gpu Gpu) (scene Scene) (environment Environment) (moving Bool)) (→ World)
      (new World
        (scene scene)
        (bvh ((if moving build-moving-bvh build-bvh) gpu (scene-triangles scene)))
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
        (normals (● (list-ref planes 0) view))
        (emission (● (list-ref planes 1) view))
        (albedo (● (list-ref planes 2) view))
        (motion (● (list-ref planes 4) view))
        (depth (● depth view))
        (camera (● kit camera))))

    ;; ---- Frames ----

    ;; By default, successive still frames trace alternate halves of a checkerboard.
    ;; The first frame and a camera or scene change cover every pixel.
    (enum TraceSampling
      (EveryPixel)
      (Checkerboard))

    ;; One frame: the G-buffers, the paths of each, which scatter at most
    ;; `bounces` times, the filters, the blended layer composed over the
    ;; first hits, the post passes. The history starts again, as for a
    ;; moving camera, when the camera's uniform or the bounces differ from
    ;; the last frame's, as they do on the first.
    (define (discard-trace-history (t Tracer)) (→ Tracer)
      (Tracer-last-set (Tracer-sky-revision-set t -1) (None)))

    (define (draw-traced (gpu Gpu) (tracer Tracer)
                         (canvas GpuTextureView)
                         (camera Camera3D)
                         (spread F32)
                         (exposure F32)
                         (bounces I64))
      (→ Tracer)
      (draw-moving-traced gpu tracer canvas camera spread exposure bounces #f))

    (define (draw-moving-traced (gpu Gpu) (tracer Tracer) (canvas GpuTextureView)
                                (camera Camera3D) (spread F32) (exposure F32) (bounces I64)
                                (moved Bool))
      (→ Tracer)
      (draw-sampled-traced gpu tracer canvas camera spread exposure bounces moved (Checkerboard)))

    (define (draw-sampled-traced (gpu Gpu) (tracer Tracer) (canvas GpuTextureView)
                                 (camera Camera3D) (spread F32) (exposure F32)
                                 (bounces I64) (moved Bool) (sampling TraceSampling))
      (→ Tracer)
      (unless (and (>= bounces 1) (<= bounces most-bounces))
        (panic (string-append "bounces outside 1 to " (show most-bounces))))
      (let* ((same-sky (= (● tracer sky-revision) (● tracer world environment revision)))
             (still (if (or (not same-sky) moved
                            (not (= bounces (● tracer bounces)))
                            (not (same-camera? (● tracer last) camera)))
                        0
                        (+ (● tracer still) 1)))
             (checker (match sampling ((Checkerboard) (> still 0)) ((EveryPixel) #f)))
             (width (● tracer targets width))
             (columns (if checker (quotient (+ width 1) 2) width))
             (encoder ((● gpu create-command-encoder)))
             (kit (● tracer kit)))
        ((● gpu write-buffer)
         (● kit camera)
         0
         (pod-bytes camera-shape (after (● tracer last) camera)))
        ((● gpu write-buffer)
         (● kit tracing)
         0
         (pod-bytes tracing-shape (tracing-of tracer spread checker 0)))
        ((● gpu write-buffer)
         (● kit blended-tracing)
         0
         (pod-bytes tracing-shape
                    (tracing-of tracer
                                spread
                                checker
                                (* (● tracer targets width) (● tracer targets height)))))
        ((● gpu write-buffer) (● kit wave) 0 (waves bounces))
        ((● gpu write-buffer) (● kit counts) 0 (zeros counts-size))
        (draw-surfaces gpu encoder tracer)
        (trace-paths gpu encoder tracer (● tracer bindings paths) columns bounces)
        (trace-blended gpu encoder tracer columns bounces)
        (let ((svgf (filter-svgf-frame gpu
                                       encoder
                                       (● tracer svgf)
                                       (= still 0)
                                       exposure
                                       (match (● tracer last) ((None) #t) (_ #f))))
              (blended-svgf (filter-blended gpu encoder tracer (= still 0) exposure)))
          (draw-composed gpu encoder tracer)
          (draw-post gpu encoder canvas (● tracer post))
          ((● gpu submit) (list ((● gpu finish) encoder)))
          (new Tracer
            (kit kit)
            (world (● tracer world))
            (targets (● tracer targets))
            (bindings (● tracer bindings))
            (svgf svgf)
            (blended-svgf blended-svgf)
            (post (● tracer post))
            (last (Some camera))
            (bounces bounces)
            (still still)
            (sky-revision (● tracer world environment revision)) (frame (+ (● tracer frame) 1))))))

    ;; The blended layer's paths, after the first hits' and from counts
    ;; cleared again, where the scene has the layer.
    (define (trace-blended (gpu Gpu)
                           (encoder GpuCommandEncoder)
                           (tracer Tracer)
                           (columns I32)
                           (bounces I64))
      (→ Unit)
      (match (● tracer bindings blended)
        ((Some groups)
         (let ((kit (● tracer kit)))
           ((● gpu copy-buffer-to-buffer) encoder
            (● kit cleared-counts)
            0
            (● kit counts)
            0
            (i64->i32 counts-size))
           (trace-paths gpu encoder tracer (● groups paths) columns bounces)))
        ((None) (unit))))

    (define (filter-blended (gpu Gpu) (encoder GpuCommandEncoder)
                            (tracer Tracer)
                            (moved Bool)
                            (exposure F32))
      (→ (Option Svgf))
      (match (● tracer blended-svgf)
        ((Some svgf)
         (Some (filter-svgf-frame gpu
                                  encoder
                                  svgf
                                  moved
                                  exposure
                                  (match (● tracer last) ((None) #t) (_ #f)))))
        ((None) (None))))

    ;; The wavefront, in one compute pass: the first hits' paths, or the
    ;; blended layer's, as `primary` and `gather` read and write; then a
    ;; bounce at a time, each step over the queue the step before appended
    ;; to, then the radiance into the noisy plane. A step runs over its
    ;; longest possible queue, one ray per sampled column per row.
    (define (trace-paths (gpu Gpu) (encoder GpuCommandEncoder)
                         (tracer Tracer)
                         (paths PathGroups) (columns I32) (bounces I64))
      (→ Unit)
      (let* ((pass ((● gpu begin-compute-pass) encoder))
             (steps (● tracer kit steps))
             (rays (● tracer kit rays))
             (bound (● tracer bindings))
             (targets (● tracer targets))
             (height (● targets height))
             (capacity (* (i32->i64 columns) (i32->i64 height))))
        ((● gpu set-compute-bind-group) pass 1 (● bound temporal-scene))
        ((● gpu set-compute-bind-group) pass 2 (● bound temporal-environment))
        (over-screen gpu pass columns height (● steps temporal) (● paths temporal))
        ((● gpu set-compute-bind-group) pass 1 (● bound primary-scene))
        ((● gpu set-compute-bind-group) pass 2 (● bound primary-environment))
        (over-screen gpu pass columns height (● steps primary) (● paths primary))
        (for-each (lambda (bounce)
                    (trace-rays gpu pass
                                (● rays occlude)
                                (● bounce occlude)
                                (Some (● bound occlude-cutout))
                                capacity)
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
        (over-screen gpu pass (● targets width) height (● steps gather) (● paths gather))
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
    (define (after (last (Option Camera3D)) (camera Camera3D)) (→ Camera3D)
      (match last
        ((Some last)
         (new Camera3D
           (view-projection (● camera view-projection))
           (inverse (● camera inverse))
           (eye (● camera eye))
           (forward (● camera forward))
           (previous (● last view-projection))
           (previous-motion (● camera previous-motion))
           (scene-time (● camera scene-time))
           (previous-heading (new Vec2f (x (● last forward x)) (y (● last forward z))))))
        ((None) camera)))

    (define (same-camera? (last (Option Camera3D)) (camera Camera3D)) (→ Bool)
      (match last
        ((Some last)
         (let ((before (pod-bytes camera-shape last)) (now (pod-bytes camera-shape camera)))
           (every? (lambda (index) (= (array-ref before index) (array-ref now index)))
                   (iota (array-length now)))))
        ((None) #f)))

    ;; A wave's uniform, its radiance starting at `start`.
    (define (tracing-of (tracer Tracer) (spread F32) (checker Bool) (start I32)) (→ Tracing)
      (new Tracing
        (view (new Vec4f (x spread) (y (i32->f32 (● tracer kit layer-size))) (z 0.0) (w 0.0)))
        (frame (new Vec4i (x (● tracer frame)) (y start)
                    (z (if (= (● tracer sky-revision) (● tracer world environment revision)) 1 0))
                    (w (if checker 1 0))))))

    ;; Every triangle's first hit, in one draw; then, where the scene has
    ;; the blended layer, every triangle again over a copy of their depth,
    ;; so that the depth test keeps the nearest blended surface in front of
    ;; them.
    (define (draw-surfaces (gpu Gpu) (encoder GpuCommandEncoder) (tracer Tracer)) (→ Unit)
      (let ((targets (● tracer targets)) (kit (● tracer kit)) (bound (● tracer bindings)))
        (surfaces-pass gpu encoder tracer
                       (● targets planes)
                       (● targets depth)
                       (ClearDepth 1.0)
                       (● kit surface)
                       (● bound surface))
        (match (pair-of (● targets blended) (● bound blended))
          ((Some (Pair b groups))
           ((● gpu copy-texture-to-texture) encoder
            (whole-texture (● targets depth texture))
            (whole-texture (● b depth texture))
            (● targets width)
            (● targets height))
           (surfaces-pass gpu encoder tracer
                          (● b planes)
                          (● b depth)
                          (KeepDepth)
                          (● kit blended-surface)
                          (● groups surface)))
          ((None) (unit)))))

    ;; Both, when both are there.
    (define (pair-of (a (Option A)) (b (Option B))) (→ (Option (Pair A B))) (∀ (A B))
      (match a
        ((Some x)
         (match b
           ((Some y) (Some (new Pair (first x) (second y))))
           ((None) (None))))
        ((None) (None))))

    (define (surfaces-pass (gpu Gpu) (encoder GpuCommandEncoder)
                           (tracer Tracer)
                           (planes (List Plane))
                           (depth Plane)
                           (depth-load DepthLoad)
                           (pipeline GpuRenderPipeline)
                           (group GpuBindGroup))
      (→ Unit)
      (let* ((scene (● tracer world scene))
             (clear (Clear (new Color (red 0.0) (green 0.0) (blue 0.0) (alpha 0.0))))
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
        ((● gpu set-pipeline) pass pipeline)
        ((● gpu set-bind-group) pass 0 group)
        ((● gpu draw) pass (i64->i32 (* 3 (● scene triangle-count))) 1 0 0)
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
    (define (wave-of (bounce I64) (bounces I64)) (→ Wave)
      (new Wave
        (step (new Vec4i (x (i64->i32 bounce)) (y (if (= bounce bounces) 1 0)) (z 0) (w 0)))
        (slots (new Vec4i
                 (x (i64->i32 (rays-word (max 0 (- bounce 1)))))
                 (y (i64->i32 (rays-word (min bounce (- most-bounces 1)))))
                 (z (i64->i32 (shadows-word (min bounce (- most-bounces 1)))))
                 (w 0)))))

    ;; Every slot of the wave for a frame of `bounces`.
    (define (waves (bounces I64)) (→ Bytes)
      (uniform-slots wave-shape (map (lambda (b) (wave-of b bounces)) (iota (+ most-bounces 1)))))

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
            (drawn (list (RenderAttachment) (TextureBinding))))
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
                               (Cons (TextureCopySrc) drawn)))
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
                                      (Nil)))))))

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
      ((surface GpuBindGroup)
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
      (concatenate (list (list (● bound surface)
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
      (list (● paths temporal) (● paths primary) (● paths gather)))

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
    (define (triangle-group (gpu Gpu) (kernel GpuComputePipeline) (scene Scene) (lit Bool))
      (→ GpuBindGroup)
      (kernel-group gpu kernel 1 "trace/triangles"
                    (append (light-entry scene lit) (list (BufferEntry 0 (● scene vertices) 0 0)
                                                          (BufferEntry 1 (● scene indices) 0 0)))))

    ;; Group 1 of a kernel that reads the scene (scene.wgsl.scm).
    (define (scene-group (gpu Gpu) (kernel GpuComputePipeline) (scene Scene) (lit Bool))
      (→ GpuBindGroup)
      (kernel-group gpu kernel
                    1
                    "trace/scene"
                    (append (light-entry scene lit) (list (BufferEntry 0 (● scene vertices) 0 0)
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
        (surface (surface-pipeline gpu "surface_fragment"))
        (blended-surface (surface-pipeline gpu "blended_fragment"))
        (compose (compose-pipeline gpu))
        (steps (path-steps gpu))
        (rays (make-ray-kernels gpu (string-append (declarations material-shape) scene-shader)))
        (camera (uniform-buffer gpu "trace/camera" (zeros (stride camera-shape))))
        (tracing (uniform-buffer gpu "trace/tracing" (zeros (stride tracing-shape))))
        (blended-tracing
         (uniform-buffer gpu "trace/blended-tracing" (zeros (stride tracing-shape))))
        (wave (uniform-buffer gpu "trace/wave" (waves most-bounces)))
        (counts (storage-buffer gpu "trace/counts" counts-size (list (CopyDst))))
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
