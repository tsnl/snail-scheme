;; A scene path traced to the canvas, a frame at a time, composed of the
;; graphics middleware:
;;
;;   surfaces   the first hits, rasterized into a G-buffer
;;              (surface.wgsl.scm)
;;   paths      a wavefront of kernels (path.wgsl.scm), each bounce's rays
;;              traced by (snail shell graphics bvh)'s queries with the
;;              scene's cutouts (scene.wgsl.scm), lit by an environment
;;              of (snail shell graphics environment)
;;   filters    (snail shell graphics svgf) over the paths and the G-buffer
;;   post       (snail shell graphics passes)'s tone mapping and FXAA
;;
;; A `Tracer` is made once for a scene and the canvas, and resized with it:
;;
;;   (let ((tracer (draw-traced (resize-tracer tracer w h) canvas camera spread exposure))) ...)
(define-library (snail shell graphics trace render)
  (export
   Tracer
   make-tracer
   resize-tracer
   retrace
   draw-traced
   tracer-frames)
  (import
   (snail core base)
   (snail shell gpu)
   (snail shell graphics pod)
   (snail shell graphics raster)
   (snail shell graphics passes)
   (snail shell graphics bvh)
   (snail shell graphics svgf)
   (snail shell graphics environment)
   (only (snail shell graphics shaders) environment-light-shader)
   (snail shell graphics trace scene)
   (snail shell graphics trace shaders))
  (begin

    ;; ---- Uniforms ----

    ;; The uniforms of a frame's paths: the camera's spread in radians a
    ;; pixel and the layers' size, then the frame's number.
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

    ;; How many times a path scatters.
    (define bounces (→ I64) 4)

    ;; ---- The tracer ----

    ;; The path kernels, each its own pipeline.
    (record Steps
      ((primary GpuComputePipeline)
       (connect GpuComputePipeline)
       (shade GpuComputePipeline)
       (gather GpuComputePipeline)))

    ;; What is made once: the scene and its BVH, the environment, the
    ;; pipelines and the uniforms.
    (record Kit
      ((scene Scene)
       (bvh Bvh)
       (environment Environment)
       (surface GpuRenderPipeline)
       (steps Steps)
       (rays RayKernels)
       (camera GpuBuffer)
       (tracing GpuBuffer)
       (wave GpuBuffer)
       (layer-size I32)))

    ;; The kit, the targets, the filters and post passes for the canvas's
    ;; size, the last frame's camera, how many frames have held still,
    ;; and how many have been drawn.
    (record Tracer
      ((kit Kit)
       (targets Targets)
       (svgf Svgf)
       (post Post)
       (last (Option Camera3D))
       (still I32)
       (frame I32)))

    (define (make-tracer (scene Scene)
                         (environment Environment)
                         (format TextureFormat)
                         (width I32)
                         (height I32)
                         (layer-size I32))
      (→ Tracer)
      (! gpu)
      (let* ((kit (new Kit
                    (scene scene)
                    (bvh (build-bvh (scene-triangles scene)))
                    (environment environment)
                    (surface (surface-pipeline))
                    (steps (path-steps))
                    (rays
                     (make-ray-kernels (string-append (declarations material-shape) scene-shader)))
                    (camera (uniform "trace/camera" (stride camera-shape)))
                    (tracing (uniform "trace/tracing" (stride tracing-shape)))
                    (wave (wave-uniform))
                    (layer-size layer-size)))
             (post (make-post format width height (Filmic)))
             (targets (targets-for kit width height)))
        (new Tracer
          (kit kit)
          (targets targets)
          (svgf (make-svgf (svgf-inputs kit targets) (● post targets light-view) width height))
          (post post)
          (last (None))
          (still 0)
          (frame 0))))

    (define (tracer-frames (tracer Tracer)) (→ I32) (● tracer still))

    (define (resize-tracer (tracer Tracer) (width I32) (height I32)) (→ Tracer) (! gpu)
      (if (and (= width (● tracer targets width)) (= height (● tracer targets height)))
          tracer
          (begin
            (release-targets (● tracer targets))
            (let* ((kit (● tracer kit))
                   (post (resize-post (● tracer post) width height))
                   (targets (targets-for kit width height)))
              (new Tracer
                (kit kit)
                (targets targets)
                (svgf (resize-svgf (● tracer svgf)
                                   (svgf-inputs kit targets)
                                   (● post targets light-view)
                                   width
                                   height))
                (post post)
                (last (● tracer last))
                (still 0)
                (frame (● tracer frame)))))))

    ;; The tracer drawing another scene in another environment with the
    ;; same pipelines, from a still camera. Its targets and the old
    ;; scene's BVH are let go; the old scene and environment are the
    ;; caller's, as they were given.
    (define (retrace (tracer Tracer) (scene Scene) (environment Environment)) (→ Tracer) (! gpu)
      (release-targets (● tracer targets))
      (release-bvh (● tracer kit bvh))
      (let* ((width (● tracer targets width))
             (height (● tracer targets height))
             (kit (Kit-environment-set (Kit-bvh-set (Kit-scene-set (● tracer kit) scene)
                                                    (build-bvh (scene-triangles scene)))
                                       environment))
             (targets (targets-for kit width height)))
        (new Tracer
          (kit kit)
          (targets targets)
          (svgf (resize-svgf (● tracer svgf)
                             (svgf-inputs kit targets)
                             (● tracer post targets light-view)
                             width
                             height))
          (post (● tracer post))
          (last (None))
          (still 0)
          (frame (● tracer frame)))))

    (define (svgf-inputs (kit Kit) (targets Targets)) (→ SvgfInputs)
      (let ((planes (● targets planes)))
        (new SvgfInputs
          (noisy (● targets noisy view))
          (normals (● (list-ref planes 0) view))
          (emission (● (list-ref planes 1) view))
          (albedo (● (list-ref planes 2) view))
          (motion (● (list-ref planes 4) view))
          (depth (● targets depth view))
          (camera (● kit camera)))))

    ;; ---- Frames ----

    ;; One frame: the G-buffer, the paths, the filters, the post passes.
    (define (draw-traced (tracer Tracer)
                         (canvas GpuTextureView)
                         (camera Camera3D)
                         (spread F32)
                         (exposure F32))
      (→ Tracer)
      (! gpu)
      (let* ((moved (moved-camera tracer camera))
             (still (if (same-camera? tracer camera) (+ (● tracer still) 1) 0))
             (encoder (create-command-encoder))
             (kit (● tracer kit))
             (targets (● tracer targets)))
        (write-buffer (● kit camera) 0 (pod-bytes camera-shape moved))
        (write-buffer (● kit tracing) 0 (pod-bytes tracing-shape (tracing-of tracer spread)))
        (write-buffer (● targets counts) 0 (make-array (* 256 (* 2 bounces)) (i32->u8 0)))
        (draw-surfaces encoder kit targets)
        (trace-paths encoder kit targets)
        (let ((svgf (filter-svgf encoder (● tracer svgf) (= still 0) exposure)))
          (draw-post encoder canvas (● tracer post))
          (submit (list (finish encoder)))
          (new Tracer
            (kit kit)
            (targets targets)
            (svgf svgf)
            (post (● tracer post))
            (last (Some moved))
            (still still)
            (frame (+ (● tracer frame) 1))))))

    ;; The wavefront, in one compute pass: the first hits' paths, then a
    ;; bounce at a time, each step over the queue the step before appended
    ;; to, then the radiance into the noisy plane.
    (define (trace-paths (encoder GpuCommandEncoder) (kit Kit) (targets Targets)) (→ Unit) (! gpu)
      (let ((pass (begin-compute-pass encoder))
            (steps (● kit steps))
            (rays (● kit rays))
            (capacity (pixels-of targets)))
        (set-compute-bind-group pass 2 (● targets primary-environment))
        (over-screen pass targets (● steps primary) (● targets primary-group))
        (for-each (lambda (bounce)
                    (trace-rays pass
                                (● rays occlude)
                                (list-ref (● targets shadow-groups) bounce)
                                (Some (● targets occlude-cutout))
                                capacity)
                    (over-queue pass
                                targets
                                (● steps connect)
                                (list-ref (● targets connect-groups) bounce)
                                (None))
                    (trace-rays pass
                                (● rays intersect)
                                (list-ref (● targets ray-groups) bounce)
                                (Some (● targets intersect-cutout))
                                capacity)
                    (set-compute-bind-group pass 2 (● targets shade-environment))
                    (over-queue pass
                                targets
                                (● steps shade)
                                (list-ref (● targets shade-groups) bounce)
                                (Some (● targets shade-scene))))
                  (iota bounces))
        (over-screen pass targets (● steps gather) (● targets gather-group))
        (end-compute-pass pass)))

    (define (over-screen (pass GpuComputePass)
                         (targets Targets)
                         (pipeline GpuComputePipeline)
                         (group GpuBindGroup))
      (→ Unit)
      (! gpu)
      (set-compute-pipeline pass pipeline)
      (set-compute-bind-group pass 0 group)
      (dispatch-workgroups pass
                           (quotient (+ (● targets width) 7) 8)
                           (quotient (+ (● targets height) 7) 8)
                           1))

    (define (over-queue (pass GpuComputePass)
                        (targets Targets)
                        (pipeline GpuComputePipeline)
                        (group GpuBindGroup)
                        (scene (Option GpuBindGroup)))
      (→ Unit)
      (! gpu)
      (set-compute-pipeline pass pipeline)
      (set-compute-bind-group pass 0 group)
      (match scene
        ((Some scene) (set-compute-bind-group pass 1 scene))
        ((None) (unit)))
      (dispatch-queue pass (pixels-of targets)))

    ;; A queue holds at most a ray a pixel.
    (define (pixels-of (targets Targets)) (→ I64)
      (* (i32->i64 (max 1 (● targets width))) (i32->i64 (max 1 (● targets height)))))

    ;; The camera with the last frame's view-projection as its previous.
    (define (moved-camera (tracer Tracer) (camera Camera3D)) (→ Camera3D)
      (match (● tracer last)
        ((Some last)
         (new Camera3D
           (view-projection (● camera view-projection))
           (inverse (● camera inverse))
           (eye (● camera eye))
           (forward (● camera forward))
           (previous (● last view-projection))
           (previous-motion (● camera previous-motion))
           (previous-heading (new Vec2f (x (● last forward x)) (y (● last forward z))))))
        ((None) camera)))

    (define (same-camera? (tracer Tracer) (camera Camera3D)) (→ Bool)
      (match (● tracer last)
        ((Some last) (and (same-matrix? (● last view-projection) (● camera view-projection))
                          (= (● last eye x) (● camera eye x))
                          (= (● last eye y) (● camera eye y))
                          (= (● last eye z) (● camera eye z))))
        ((None) #f)))

    (define (same-matrix? (a Mat4x4f) (b Mat4x4f)) (→ Bool)
      (and (same-column? (● a x) (● b x))
           (same-column? (● a y) (● b y))
           (same-column? (● a z) (● b z))
           (same-column? (● a w) (● b w))))

    (define (same-column? (a Vec4f) (b Vec4f)) (→ Bool)
      (and (= (● a x) (● b x)) (= (● a y) (● b y)) (= (● a z) (● b z)) (= (● a w) (● b w))))

    (define (tracing-of (tracer Tracer) (spread F32)) (→ Tracing)
      (new Tracing
        (view (new Vec4f (x spread) (y (i32->f32 (● tracer kit layer-size))) (z 0.0) (w 0.0)))
        (frame (new Vec4i (x (● tracer frame)) (y 0) (z 0) (w 0)))))

    ;; Every triangle's first hit, in one draw.
    (define (draw-surfaces (encoder GpuCommandEncoder) (kit Kit) (targets Targets)) (→ Unit) (! gpu)
      (let* ((pass (begin-render-pass encoder
                                      (new RenderPassDescriptor
                                        (colors (map (lambda (plane)
                                                       (Some (new ColorAttachment
                                                               (view (● plane view))
                                                               (load (Clear (new Color
                                                                              (red 0.0)
                                                                              (green 0.0)
                                                                              (blue 0.0)
                                                                              (alpha 0.0))))
                                                               (store #t))))
                                                     (● targets planes)))
                                        (depth (Some (new DepthAttachment
                                                       (view (● targets depth view))
                                                       (load (ClearDepth 1.0))
                                                       (store #t))))))))
        (set-pipeline pass (● kit surface))
        (set-bind-group pass 0 (● targets surface-group))
        (set-index-buffer pass (● kit scene indices) (Uint32Index) 0)
        (draw-indexed pass (i64->i32 (* 3 (● kit scene triangle-count))) 1 0 0 0)
        (end-pass pass)))

    ;; ---- Queues ----

    ;; The words of bounce b's counts: its rays at 64b, its shadow rays
    ;; 64 (bounces + b), each count alone in 256 bytes so a query can bind
    ;; it.
    (define (rays-word (bounce I64)) (→ I64) (* 64 bounce))
    (define (shadows-word (bounce I64)) (→ I64) (* 64 (+ bounces bounce)))

    ;; Slot b for bounce b's steps: primary's at 0, shade's at the bounce
    ;; its rays leave from, the last only adding what they hit.
    (define (wave-uniform) (→ GpuBuffer) (! gpu)
      (let ((b (uniform "trace/wave" (* 256 (+ bounces 1)))))
        (write-buffer b
                      0
                      (fold-left array-append
                                 (make-array 0 (i32->u8 0))
                                 (map (lambda (bounce)
                                        (let ((bytes (pod-bytes wave-shape (wave-of bounce))))
                                          (array-append bytes
                                                        (make-array (- 256 (array-length bytes))
                                                                    (i32->u8 0)))))
                                      (iota (+ bounces 1)))))
        b))

    (define (wave-of (bounce I64)) (→ Wave)
      (new Wave
        (step (new Vec4i (x (i64->i32 bounce)) (y (if (= bounce bounces) 1 0)) (z 0) (w 0)))
        (slots (new Vec4i
                 (x (i64->i32 (rays-word (max 0 (- bounce 1)))))
                 (y (i64->i32 (rays-word (min bounce (- bounces 1)))))
                 (z (i64->i32 (shadows-word (min bounce (- bounces 1)))))
                 (w 0)))))

    ;; ---- Targets ----

    ;; The G-buffer's planes and depth; the noisy plane; the queues: two
    ;; of rays, which a bounce reads one of and appends to the other, and
    ;; one of shadow rays; each path's radiance and the counts; and the
    ;; groups over them, one per bounce where a step's queues or slot
    ;; change with it.
    (record Targets
      ((width I32)
       (height I32)
       (planes (List Plane))
       (depth Plane)
       (noisy Plane)
       (queues (List GpuBuffer))
       (shadows GpuBuffer)
       (radiance GpuBuffer)
       (counts GpuBuffer)
       (surface-group GpuBindGroup)
       (primary-group GpuBindGroup)
       (shadow-groups (List GpuBindGroup))
       (connect-groups (List GpuBindGroup))
       (ray-groups (List GpuBindGroup))
       (shade-groups (List GpuBindGroup))
       (gather-group GpuBindGroup)
       (occlude-cutout GpuBindGroup)
       (intersect-cutout GpuBindGroup)
       (shade-scene GpuBindGroup)
       (primary-environment GpuBindGroup)
       (shade-environment GpuBindGroup)))

    (define planes-formats
      (→ (List TextureFormat))
      (list (Rgba16Float) (Rgba16Float) (Rgba8UnormSrgb) (Rgba8Unorm) (Rg16Float)))

    (define (targets-for (kit Kit) (width I32) (height I32)) (→ Targets) (! gpu)
      (let* ((pixels (* (i32->i64 (max 1 width)) (i32->i64 (max 1 height))))
             (planes (map (lambda (format)
                            (screen-plane "trace/gbuffer"
                                          width
                                          height
                                          format
                                          (list (RenderAttachment) (TextureBinding))))
                          planes-formats))
             (depth (screen-plane "trace/depth"
                                  width
                                  height
                                  (Depth32Float)
                                  (list (RenderAttachment) (TextureBinding))))
             (noisy (screen-plane "trace/noisy"
                                  width
                                  height
                                  (Rgba16Float)
                                  (list (StorageBinding) (TextureBinding))))
             (queues
              (map (lambda (index) (storage "trace/rays" (* ray-size pixels) (Nil))) (iota 2)))
             (shadows (storage "trace/shadows" (* ray-size pixels) (Nil)))
             (radiance (storage "trace/radiance" (* 16 pixels) (Nil)))
             (counts (storage "trace/counts" (* 256 (* 2 bounces)) (list (CopyDst)))))
        (new Targets
          (width width)
          (height height)
          (planes planes)
          (depth depth)
          (noisy noisy)
          (queues queues)
          (shadows shadows)
          (radiance radiance)
          (counts counts)
          (surface-group (surface-group kit))
          (primary-group (step-group (● kit steps primary)
                                     (list (BufferEntry 0 (● kit camera) 0 0)
                                           (BufferEntry 1 (● kit tracing) 0 0)
                                           (wave-entry kit 0)
                                           (BufferEntry 4 (list-ref queues 0) 0 0)
                                           (BufferEntry 5 shadows 0 0)
                                           (BufferEntry 6 counts 0 0)
                                           (BufferEntry 7 radiance 0 0)
                                           (TextureEntry 9 (● (list-ref planes 0) view))
                                           (TextureEntry 10 (● (list-ref planes 1) view))
                                           (TextureEntry 11 (● (list-ref planes 2) view))
                                           (TextureEntry 12 (● (list-ref planes 3) view))
                                           (TextureEntry 13 (● depth view)))))
          (shadow-groups (per-bounce (lambda (bounce)
                                       (ray-group (● kit rays occlude)
                                                  (● kit bvh)
                                                  shadows
                                                  counts
                                                  (count-at (shadows-word bounce))))))
          (connect-groups (per-bounce (lambda (bounce)
                                        (step-group (● kit steps connect)
                                                    (list (wave-entry kit bounce)
                                                          (BufferEntry 5 shadows 0 0)
                                                          (BufferEntry 6 counts 0 0)
                                                          (BufferEntry 7 radiance 0 0))))))
          (ray-groups (per-bounce (lambda (bounce)
                                    (ray-group (● kit rays intersect)
                                               (● kit bvh)
                                               (list-ref queues (remainder bounce 2))
                                               counts
                                               (count-at (rays-word bounce))))))
          (shade-groups (per-bounce (lambda (bounce)
                                      (step-group (● kit steps shade)
                                                  (list (BufferEntry 1 (● kit tracing) 0 0)
                                                        (wave-entry kit (+ bounce 1))
                                                        (BufferEntry 3
                                                                     (list-ref queues
                                                                               (remainder bounce 2))
                                                                     0
                                                                     0)
                                                        (BufferEntry 4
                                                                     (list-ref queues
                                                                               (remainder
                                                                                (+ bounce 1)
                                                                                2))
                                                                     0
                                                                     0)
                                                        (BufferEntry 5 shadows 0 0)
                                                        (BufferEntry 6 counts 0 0)
                                                        (BufferEntry 7 radiance 0 0))))))
          (gather-group (step-group (● kit steps gather)
                                    (list (BufferEntry 7 radiance 0 0)
                                          (TextureEntry 13 (● depth view))
                                          (TextureEntry 14 (● noisy view)))))
          (occlude-cutout (scene-group (● kit rays occlude) (● kit scene)))
          (intersect-cutout (scene-group (● kit rays intersect) (● kit scene)))
          (shade-scene (scene-group (● kit steps shade) (● kit scene)))
          (primary-environment (environment-group (● kit steps primary) (● kit environment)))
          (shade-environment (environment-group (● kit steps shade) (● kit environment))))))

    (define (per-bounce (make (Fn I64 → GpuBindGroup ! gpu))) (→ (List GpuBindGroup)) (! gpu)
      (map make (iota bounces)))

    (define (count-at (word I64)) (→ I32) (i64->i32 (* 4 word)))

    (define (wave-entry (kit Kit) (bounce I64)) (→ BindGroupEntry)
      (BufferEntry 2 (● kit wave) (i64->i32 (* 256 bounce)) 256))

    (define (step-group (pipeline GpuComputePipeline) (entries (List BindGroupEntry)))
      (→ GpuBindGroup)
      (! gpu)
      (group "trace/step" (ComputePipeline pipeline) 0 entries))

    ;; Group 1 of a kernel that reads the scene (scene.wgsl.scm).
    (define (scene-group (pipeline GpuComputePipeline) (scene Scene)) (→ GpuBindGroup) (! gpu)
      (group "trace/scene"
             (ComputePipeline pipeline)
             1
             (list (BufferEntry 0 (● scene vertices) 0 0)
                   (BufferEntry 1 (● scene indices) 0 0)
                   (BufferEntry 2 (● scene materials) 0 0)
                   (TextureEntry 3 (● scene layers-view))
                   (SamplerEntry 4 (● scene sampler)))))

    (define (surface-group (kit Kit)) (→ GpuBindGroup) (! gpu)
      (let ((scene (● kit scene)))
        (group "trace/surface"
               (RenderPipeline (● kit surface))
               0
               (list (BufferEntry 0 (● kit camera) 0 0)
                     (BufferEntry 1 (● scene vertices) 0 0)
                     (BufferEntry 2 (● scene materials) 0 0)
                     (TextureEntry 3 (● scene layers-view))
                     (SamplerEntry 4 (● scene sampler))))))

    (define (release-targets (targets Targets)) (→ Unit) (! gpu)
      (for-each (lambda (group) (destroy (BindGroupObject group)))
                (concatenate (list (list (● targets surface-group)
                                         (● targets primary-group)
                                         (● targets gather-group)
                                         (● targets occlude-cutout)
                                         (● targets intersect-cutout)
                                         (● targets shade-scene)
                                         (● targets primary-environment)
                                         (● targets shade-environment))
                                   (● targets shadow-groups)
                                   (● targets connect-groups)
                                   (● targets ray-groups)
                                   (● targets shade-groups))))
      (for-each (lambda (buffer) (destroy (BufferObject buffer)))
                (concatenate (list (● targets queues)
                                   (list (● targets shadows)
                                         (● targets radiance)
                                         (● targets counts)))))
      (for-each (lambda (plane)
                  (destroy (ViewObject (● plane view)))
                  (destroy (TextureObject (● plane texture))))
                (Cons (● targets depth) (Cons (● targets noisy) (● targets planes)))))

    (define (screen-plane (label String)
                          (width I32)
                          (height I32)
                          (format TextureFormat)
                          (usage (List TextureUsage)))
      (→ Plane)
      (! gpu)
      (let ((texture (create-texture (new TextureDescriptor
                                       (label label)
                                       (width (max 1 width))
                                       (height (max 1 height))
                                       (layers 1)
                                       (mips 1)
                                       (format format)
                                       (usage usage)))))
        (new Plane (texture texture) (view (view-of texture 1)))))

    (define (storage (label String) (size I64) (more (List BufferUsage))) (→ GpuBuffer) (! gpu)
      (create-buffer (new BufferDescriptor
                       (label label)
                       (size (i64->i32 (max 16 size)))
                       (usage (Cons (Storage) more)))))

    ;; ---- Pipelines ----

    (define (path-steps) (→ Steps) (! gpu)
      (let ((module (create-shader-module (new ShaderModuleDescriptor
                                            (label "trace/path")
                                            (code
                                             (concatenate-strings (list (declarations camera-shape)
                                                                        (declarations tracing-shape)
                                                                        (declarations wave-shape)
                                                                        (declarations
                                                                         material-shape)
                                                                        scene-shader
                                                                        environment-light-shader
                                                                        path-shader)))))))
        (new Steps
          (primary (step module "primary"))
          (connect (step module "connect"))
          (shade (step module "shade"))
          (gather (step module "gather")))))

    (define (concatenate-strings (parts (List String))) (→ String)
      (fold-left (lambda (text part) (string-append text part)) "" parts))

    (define (step (module GpuShaderModule) (entry String)) (→ GpuComputePipeline) (! gpu)
      (create-compute-pipeline (new ComputePipelineDescriptor
                                 (label (string-append "trace/" entry))
                                 (module module)
                                 (entry entry))))

    (define (surface-pipeline) (→ GpuRenderPipeline) (! gpu)
      (create-render-pipeline
       (new RenderPipelineDescriptor
         (label "trace/surface")
         (module (create-shader-module (new ShaderModuleDescriptor
                                         (label "trace/surface")
                                         (code (string-append (declarations camera-shape)
                                                              (string-append
                                                               (declarations material-shape)
                                                               surface-shader))))))
         (vertex-entry "surface_vertex")
         (buffers (Nil))
         (fragment (Some (new FragmentState
                           (entry "surface_fragment")
                           (targets (map (lambda (format)
                                           (Some (new ColorTarget (format format) (blend (None)))))
                                         planes-formats)))))
         (topology (TriangleList))
         (cull (CullNone))
         (depth
          (Some (new DepthState (format (Depth32Float)) (write #t) (compare (CompareLess))))))))

    (define (uniform (label String) (size I64)) (→ GpuBuffer) (! gpu)
      (create-buffer (new BufferDescriptor
                       (label label)
                       (size (i64->i32 size))
                       (usage (list (Uniform) (CopyDst))))))

    (define (group (label String)
                   (pipeline GpuPipeline)
                   (index I32)
                   (entries (List BindGroupEntry)))
      (→ GpuBindGroup)
      (! gpu)
      (create-bind-group
       (new BindGroupDescriptor (label label) (pipeline pipeline) (group index) (entries entries))))

    ))
