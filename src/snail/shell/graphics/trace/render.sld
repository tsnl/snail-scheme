;; A scene path traced to the canvas, a frame at a time: its first hits
;; rasterized into a G-buffer (surface.wgsl.scm), a path from each
;; (path.wgsl.scm) through the scene's BVH, the paths averaged with those
;; of earlier frames while the camera holds still (accumulate.wgsl.scm),
;; and the average tone-mapped and smoothed into the canvas by
;; (snail shell graphics passes)'s `Post`. A `Tracer` is made once for a
;; scene and the canvas, and resized with it:
;;
;;   (let ((tracer (draw-traced (resize-tracer tracer w h) canvas camera sky))) ...)
(define-library (snail shell graphics trace render)
  (export
   Sky
   Tracer
   make-tracer
   resize-tracer
   draw-traced
   tracer-frames)
  (import
   (snail core base)
   (snail shell gpu)
   (snail shell graphics pod)
   (snail shell graphics raster)
   (snail shell graphics passes)
   (snail shell graphics trace scene)
   (snail shell graphics trace bvh)
   (snail shell graphics trace shaders))
  (begin

    ;; ---- Light ----

    ;; The direction toward the sun, the cosine of its angular radius, and
    ;; the irradiance it gives a surface facing it; the sky's zenith and
    ;; horizon colors, and the ground's, each with a strength in w.
    (record Sky
      ((sun Vec4f)
       (sun-light Vec4f)
       (zenith Vec4f)
       (horizon Vec4f)
       (ground Vec4f)))

    ;; The uniforms of a frame's paths: the sky, the camera's spread in
    ;; radians a pixel and the layers' size, then the frame's number, how
    ;; many bounces a path takes, and how many frames the history holds.
    (record Tracing
      ((sun Vec4f)
       (sun-light Vec4f)
       (zenith Vec4f)
       (horizon Vec4f)
       (ground Vec4f)
       (view Vec4f)
       (frame Vec4i))
      (deriving Pod))

    (define tracing-shape (→ (Shape Tracing)) (shape))
    (define camera-shape (→ (Shape Camera3D)) (shape))
    (define material-shape (→ (Shape SurfaceMaterial)) (shape))

    ;; ---- The tracer ----

    ;; What is made once: the scene and its BVH, the pipelines and the
    ;; uniforms, and how many bounces a path takes.
    (record Kit
      ((scene Scene)
       (bvh Bvh)
       (surface GpuRenderPipeline)
       (path GpuComputePipeline)
       (accumulate GpuComputePipeline)
       (camera GpuBuffer)
       (tracing GpuBuffer)
       (bounces I32)
       (layer-size I32)))

    ;; The kit, the targets and post passes for the canvas's size, the
    ;; last frame's camera, how many frames have held still, and how many
    ;; have been drawn.
    (record Tracer
      ((kit Kit)
       (targets Targets)
       (post Post)
       (last (Option Camera3D))
       (still I32)
       (frame I32)))

    ;; The G-buffer's planes, the noisy paths, the two histories the
    ;; average alternates between, and the groups over them.
    (record Targets
      ((width I32)
       (height I32)
       (planes (List Plane))
       (depth Plane)
       (noisy Plane)
       (histories (List Plane))
       (surface-group GpuBindGroup)
       (path-group GpuBindGroup)
       (accumulate-groups (List GpuBindGroup))))

    (define (make-tracer (scene Scene) (format TextureFormat) (width I32) (height I32) (layer-size I32))
      (→ Tracer)
      (! gpu)
      (let ((kit (new Kit
                   (scene scene)
                   (bvh (build-bvh scene))
                   (surface (surface-pipeline))
                   (path (kernel path-shader "path" "trace_main"))
                   (accumulate (kernel accumulate-shader "accumulate" "accumulate_main"))
                   (camera (uniform "trace/camera" (stride camera-shape)))
                   (tracing (uniform "trace/tracing" (stride tracing-shape)))
                   (bounces 4)
                   (layer-size layer-size)))
            (post (make-post format width height)))
        (new Tracer
          (kit kit)
          (targets (targets-for kit post width height))
          (post post)
          (last (None))
          (still 0)
          (frame 0))))

    (define (tracer-frames (tracer Tracer)) (→ I32) (● tracer still))

    ;; ---- Frames ----

    ;; One frame: the G-buffer, the paths, the average, the post passes.
    (define (draw-traced (tracer Tracer) (canvas GpuTextureView) (camera Camera3D) (sky Sky) (spread F32))
      (→ Tracer)
      (! gpu)
      (let* ((moved (moved-camera tracer camera))
             (still (if (same-camera? tracer camera) (+ (● tracer still) 1) 0))
             (encoder (create-command-encoder))
             (kit (● tracer kit))
             (targets (● tracer targets)))
        (write-buffer (● kit camera) 0 (pod-bytes camera-shape moved))
        (write-buffer (● kit tracing) 0 (pod-bytes tracing-shape (tracing-of tracer sky spread still)))
        (draw-surfaces encoder kit targets)
        (let ((pass (begin-compute-pass encoder)))
          (set-compute-pipeline pass (● kit path))
          (set-compute-bind-group pass 0 (● targets path-group))
          (dispatch-workgroups pass (groups-of (● targets width)) (groups-of (● targets height)) 1)
          (set-compute-pipeline pass (● kit accumulate))
          (set-compute-bind-group pass 0 (list-ref (● targets accumulate-groups) (i32->i64 (remainder (● tracer frame) 2))))
          (dispatch-workgroups pass (groups-of (● targets width)) (groups-of (● targets height)) 1)
          (end-compute-pass pass))
        (draw-post encoder canvas (● tracer post))
        (submit (list (finish encoder)))
        (Tracer-frame-set (Tracer-still-set (Tracer-last-set tracer (Some moved)) still) (+ (● tracer frame) 1))))

    (define (groups-of (size I32)) (→ I32) (quotient (+ size 7) 8))

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
           (previous-motion (● camera previous-motion))))
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

    (define (tracing-of (tracer Tracer) (sky Sky) (spread F32) (still I32)) (→ Tracing)
      (new Tracing
        (sun (● sky sun))
        (sun-light (● sky sun-light))
        (zenith (● sky zenith))
        (horizon (● sky horizon))
        (ground (● sky ground))
        (view (new Vec4f (x spread) (y (i32->f32 (● tracer kit layer-size))) (z 0.0) (w 0.0)))
        (frame (new Vec4i (x (● tracer frame)) (y (● tracer kit bounces)) (z still) (w 0)))))

    ;; Every triangle's first hit, in one draw.
    (define (draw-surfaces (encoder GpuCommandEncoder) (kit Kit) (targets Targets)) (→ Unit) (! gpu)
      (let* ((pass (begin-render-pass encoder
                                      (new RenderPassDescriptor
                                        (colors (map (lambda (plane)
                                                       (Some (new ColorAttachment
                                                               (view (● plane view))
                                                               (load (Clear (new Color (red 0.0) (green 0.0) (blue 0.0) (alpha 0.0))))
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

    ;; ---- Targets ----

    (define planes-formats
      (→ (List TextureFormat))
      (list (Rgba16Float) (Rgba16Float) (Rgba8UnormSrgb) (Rgba8Unorm) (Rg16Float)))

    (define (resize-tracer (tracer Tracer) (width I32) (height I32)) (→ Tracer) (! gpu)
      (if (and (= width (● tracer targets width)) (= height (● tracer targets height)))
          tracer
          (begin
            (release-targets (● tracer targets))
            (let ((post (resize-post (● tracer post) width height)))
              (new Tracer
                (kit (● tracer kit))
                (targets (targets-for (● tracer kit) post width height))
                (post post)
                (last (● tracer last))
                (still 0)
                (frame (● tracer frame)))))))

    (define (targets-for (kit Kit) (post Post) (width I32) (height I32)) (→ Targets) (! gpu)
      (let* ((planes (map (lambda (format) (screen-plane "trace/gbuffer" width height format (list (RenderAttachment) (TextureBinding))))
                          planes-formats))
             (depth (screen-plane "trace/depth" width height (Depth32Float) (list (RenderAttachment) (TextureBinding))))
             (noisy (screen-plane "trace/noisy" width height (Rgba16Float) (list (StorageBinding) (TextureBinding))))
             (histories (map (lambda (index) (screen-plane "trace/history" width height (Rgba16Float) (list (StorageBinding) (TextureBinding))))
                             (iota 2)))
             (scene (● kit scene))
             (light (● post targets light-view)))
        (new Targets
          (width width)
          (height height)
          (planes planes)
          (depth depth)
          (noisy noisy)
          (histories histories)
          (surface-group (group "trace/surface"
                                (RenderPipeline (● kit surface))
                                (list (BufferEntry 0 (● kit camera) 0 0)
                                      (BufferEntry 1 (● scene vertices) 0 0)
                                      (BufferEntry 2 (● scene materials) 0 0)
                                      (TextureEntry 3 (● scene layers-view))
                                      (SamplerEntry 4 (● scene sampler)))))
          (path-group (group "trace/path"
                             (ComputePipeline (● kit path))
                             (list (BufferEntry 0 (● kit camera) 0 0)
                                   (BufferEntry 1 (● kit tracing) 0 0)
                                   (BufferEntry 2 (● scene vertices) 0 0)
                                   (BufferEntry 3 (● scene indices) 0 0)
                                   (BufferEntry 4 (● kit bvh nodes) 0 0)
                                   (BufferEntry 5 (● scene materials) 0 0)
                                   (TextureEntry 6 (● scene layers-view))
                                   (SamplerEntry 7 (● scene sampler))
                                   (TextureEntry 8 (● (list-ref planes 0) view))
                                   (TextureEntry 9 (● (list-ref planes 1) view))
                                   (TextureEntry 10 (● (list-ref planes 2) view))
                                   (TextureEntry 11 (● (list-ref planes 3) view))
                                   (TextureEntry 12 (● depth view))
                                   (TextureEntry 13 (● noisy view)))))
          (accumulate-groups
           (map (lambda (index)
                  (group "trace/accumulate"
                         (ComputePipeline (● kit accumulate))
                         (list (TextureEntry 0 (● noisy view))
                               (TextureEntry 1 (● (list-ref histories (- 1 index)) view))
                               (TextureEntry 2 (● (list-ref histories index) view))
                               (TextureEntry 3 light)
                               (BufferEntry 4 (● kit tracing) 0 0))))
                (iota 2))))))

    (define (release-targets (targets Targets)) (→ Unit) (! gpu)
      (for-each (lambda (group) (destroy (BindGroupObject group)))
                (Cons (● targets surface-group) (Cons (● targets path-group) (● targets accumulate-groups))))
      (for-each (lambda (plane)
                  (destroy (ViewObject (● plane view)))
                  (destroy (TextureObject (● plane texture))))
                (Cons (● targets depth) (Cons (● targets noisy) (append (● targets planes) (● targets histories))))))

    (define (screen-plane (label String) (width I32) (height I32) (format TextureFormat) (usage (List TextureUsage)))
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

    ;; ---- Pipelines ----

    (define (declared (code String)) (→ String)
      (string-append (declarations camera-shape)
                     (declarations tracing-shape)
                     (declarations material-shape)
                     code))

    (define (kernel (code String) (label String) (entry String)) (→ GpuComputePipeline) (! gpu)
      (create-compute-pipeline
       (new ComputePipelineDescriptor
         (label (string-append "trace/" label))
         (module (create-shader-module (new ShaderModuleDescriptor (label (string-append "trace/" label)) (code (declared code)))))
         (entry entry))))

    (define (surface-pipeline) (→ GpuRenderPipeline) (! gpu)
      (create-render-pipeline
       (new RenderPipelineDescriptor
         (label "trace/surface")
         (module (create-shader-module (new ShaderModuleDescriptor
                                         (label "trace/surface")
                                         (code (string-append (declarations camera-shape)
                                                              (declarations material-shape)
                                                              surface-shader)))))
         (vertex-entry "surface_vertex")
         (buffers (Nil))
         (fragment (Some (new FragmentState
                           (entry "surface_fragment")
                           (targets (map (lambda (format) (Some (new ColorTarget (format format) (blend (None)))))
                                         planes-formats)))))
         (topology (TriangleList))
         (cull (CullNone))
         (depth (Some (new DepthState (format (Depth32Float)) (write #t) (compare (CompareLess))))))))

    (define (uniform (label String) (size I64)) (→ GpuBuffer) (! gpu)
      (create-buffer (new BufferDescriptor (label label) (size (i64->i32 size)) (usage (list (Uniform) (CopyDst))))))

    (define (group (label String) (pipeline GpuPipeline) (entries (List BindGroupEntry))) (→ GpuBindGroup) (! gpu)
      (create-bind-group (new BindGroupDescriptor (label label) (pipeline pipeline) (group 0) (entries entries))))

    ))
