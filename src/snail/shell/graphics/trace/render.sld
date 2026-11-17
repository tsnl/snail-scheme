;; A scene path traced to the canvas, a frame at a time: its first hits
;; rasterized into a G-buffer (surface.wgsl.scm), a path from each
;; (path.wgsl.scm) through the scene's BVH, the paths filtered over space
;; and time (svgf.wgsl.scm), and the light tone-mapped and smoothed into
;; the canvas by
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

    ;; The filters' uniform, one slot each: the longest history and the
    ;; least weight a frame gets, then an à-trous level's step.
    (record Filtering
      ((limits Vec4f))
      (deriving Pod))

    (define filtering-shape (→ (Shape Filtering)) (shape))
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
       (temporal GpuComputePipeline)
       (variance GpuComputePipeline)
       (atrous GpuComputePipeline)
       (remodulate GpuComputePipeline)
       (filtering GpuBuffer)
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

    ;; The G-buffer's planes, the noisy paths, the filters' planes, and the
    ;; groups over them. A history is two planes, last frame's and this
    ;; frame's, which change places each frame.
    (record Targets
      ((width I32)
       (height I32)
       (planes (List Plane))
       (depth Plane)
       (noisy Plane)
       (integrated Plane)
       (ping Plane)
       (pong Plane)
       (colors (List Plane))
       (moments (List Plane))
       (places (List Plane))
       (surface-group GpuBindGroup)
       (path-group GpuBindGroup)
       (temporal-groups (List GpuBindGroup))
       (variance-groups (List GpuBindGroup))
       (atrous-groups (List GpuBindGroup))
       (remodulate-group GpuBindGroup)))

    (define (make-tracer (scene Scene) (format TextureFormat) (width I32) (height I32) (layer-size I32))
      (→ Tracer)
      (! gpu)
      (let ((kit (new Kit
                   (scene scene)
                   (bvh (build-bvh scene))
                   (surface (surface-pipeline))
                   (path (kernel path-shader "path" "trace_main"))
                   (temporal (kernel svgf-shader "svgf/temporal" "temporal"))
                   (variance (kernel svgf-shader "svgf/variance" "variance"))
                   (atrous (kernel svgf-shader "svgf/atrous" "atrous"))
                   (remodulate (kernel svgf-shader "svgf/remodulate" "remodulate"))
                   (filtering (uniform "trace/filtering" (* 6 256)))
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
    (define (draw-traced (tracer Tracer)
                         (canvas GpuTextureView)
                         (camera Camera3D)
                         (sky Sky)
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
        (write-buffer (● kit tracing) 0 (pod-bytes tracing-shape (tracing-of tracer sky spread still)))
        (draw-surfaces encoder kit targets)
        (write-buffer (● kit filtering) 0 (filtering-bytes (= still 0) exposure))
        (filter-paths encoder kit targets (i32->i64 (remainder (● tracer frame) 2)))
        (draw-post encoder canvas (● tracer post))
        (submit (list (finish encoder)))
        (Tracer-frame-set (Tracer-still-set (Tracer-last-set tracer (Some moved)) still) (+ (● tracer frame) 1))))

    (define (groups-of (size I32)) (→ I32) (quotient (+ size 7) 8))

    ;; The paths, then the filters: temporal, variance and the first
    ;; à-trous level, whose output is kept as this frame's history, then
    ;; four more levels and the light.
    (define (filter-paths (encoder GpuCommandEncoder) (kit Kit) (targets Targets) (parity I64)) (→ Unit) (! gpu)
      (let ((first (begin-compute-pass encoder)))
        (dispatch-over-screen first targets (● kit path) (● targets path-group))
        (dispatch-over-screen first targets (● kit temporal) (list-ref (● targets temporal-groups) parity))
        (dispatch-over-screen first targets (● kit variance) (list-ref (● targets variance-groups) parity))
        (dispatch-over-screen first targets (● kit atrous) (list-ref (● targets atrous-groups) 0))
        (end-compute-pass first))
      (copy-texture-to-texture encoder
                               (whole-texture (● targets pong texture))
                               (whole-texture (● (list-ref (● targets colors) parity) texture))
                               (● targets width)
                               (● targets height))
      (let ((rest (begin-compute-pass encoder)))
        (for-each (lambda (level) (dispatch-over-screen rest targets (● kit atrous) (list-ref (● targets atrous-groups) level)))
                  (list 1 2 3 4))
        (dispatch-over-screen rest targets (● kit remodulate) (● targets remodulate-group))
        (end-compute-pass rest)))

    (define (dispatch-over-screen (pass GpuComputePass) (targets Targets) (pipeline GpuComputePipeline) (group GpuBindGroup))
      (→ Unit)
      (! gpu)
      (set-compute-pipeline pass pipeline)
      (set-compute-bind-group pass 0 group)
      (dispatch-workgroups pass (groups-of (● targets width)) (groups-of (● targets height)) 1))

    ;; Slot 0 for the temporal filter and the light: a moving camera keeps
    ;; 32 frames at most and gives each at least a fifth, a still one keeps
    ;; averaging; and the exposure. Slots 1 to 5, the à-trous levels' steps.
    (define (filtering-bytes (moved Bool) (exposure F32)) (→ Bytes)
      (fold-left array-append
                 (make-array 0 (i32->u8 0))
                 (map (lambda (limits)
                        (let ((bytes (pod-bytes filtering-shape (new Filtering (limits limits)))))
                          (array-append bytes (make-array (- 256 (array-length bytes)) (i32->u8 0)))))
                      (Cons (if moved
                                (new Vec4f (x 32.0) (y 0.2) (z 0.0) (w exposure))
                                (new Vec4f (x 4096.0) (y 0.0) (z 0.0) (w exposure)))
                            (map (lambda (stride) (new Vec4f (x 0.0) (y 0.0) (z stride) (w 0.0)))
                                 (list 1.0 2.0 4.0 8.0 16.0))))))

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
             (filter-plane (lambda ((label String) (format TextureFormat)) (→ Plane) (! gpu)
                             (screen-plane label width height format (list (StorageBinding) (TextureBinding) (TextureCopySrc) (TextureCopyDst)))))
             (integrated (filter-plane "svgf/integrated" (Rgba16Float)))
             (ping (filter-plane "svgf/ping" (Rgba16Float)))
             (pong (filter-plane "svgf/pong" (Rgba16Float)))
             (colors (map (lambda (index) (filter-plane "svgf/color" (Rgba16Float))) (iota 2)))
             (moments (map (lambda (index) (filter-plane "svgf/moments" (Rgba16Float))) (iota 2)))
             (places (map (lambda (index) (filter-plane "svgf/place" (Rgba32Float))) (iota 2)))
             (scene (● kit scene))
             (light (● post targets light-view)))
        (new Targets
          (width width)
          (height height)
          (planes planes)
          (depth depth)
          (noisy noisy)
          (integrated integrated)
          (ping ping)
          (pong pong)
          (colors colors)
          (moments moments)
          (places places)
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
          (temporal-groups
           (map (lambda (index)
                  (group "svgf/temporal"
                         (ComputePipeline (● kit temporal))
                         (list (TextureEntry 0 (● noisy view))
                               (TextureEntry 1 (● (list-ref planes 2) view))
                               (TextureEntry 2 (● (list-ref planes 1) view))
                               (TextureEntry 3 (● (list-ref planes 0) view))
                               (TextureEntry 4 (● depth view))
                               (TextureEntry 5 (● (list-ref planes 4) view))
                               (TextureEntry 6 (● (list-ref colors (- 1 index)) view))
                               (TextureEntry 7 (● (list-ref moments (- 1 index)) view))
                               (TextureEntry 8 (● (list-ref places (- 1 index)) view))
                               (TextureEntry 9 (● integrated view))
                               (TextureEntry 10 (● (list-ref moments index) view))
                               (TextureEntry 11 (● (list-ref places index) view))
                               (BufferEntry 16 (● kit camera) 0 0)
                               (BufferEntry 17 (● kit filtering) 0 256))))
                (iota 2)))
          (variance-groups
           (map (lambda (index)
                  (group "svgf/variance"
                         (ComputePipeline (● kit variance))
                         (list (TextureEntry 0 (● noisy view))
                               (TextureEntry 3 (● (list-ref planes 0) view))
                               (TextureEntry 4 (● depth view))
                               (TextureEntry 12 (● integrated view))
                               (TextureEntry 13 (● ping view))
                               (TextureEntry 14 (● (list-ref moments index) view))
                               (BufferEntry 16 (● kit camera) 0 0))))
                (iota 2)))
          (atrous-groups
           (map (lambda (level)
                  (let ((from (if (= (remainder level 2) 0) ping pong)) (to (if (= (remainder level 2) 0) pong ping)))
                    (group "svgf/atrous"
                           (ComputePipeline (● kit atrous))
                           (list (TextureEntry 0 (● noisy view))
                                 (TextureEntry 3 (● (list-ref planes 0) view))
                                 (TextureEntry 4 (● depth view))
                                 (TextureEntry 12 (● from view))
                                 (TextureEntry 13 (● to view))
                                 (BufferEntry 16 (● kit camera) 0 0)
                                 (BufferEntry 17 (● kit filtering) (i64->i32 (* 256 (+ level 1))) 256)))))
                (iota 5)))
          (remodulate-group (group "svgf/remodulate"
                                   (ComputePipeline (● kit remodulate))
                                   (list (TextureEntry 0 (● noisy view))
                                         (TextureEntry 1 (● (list-ref planes 2) view))
                                         (TextureEntry 2 (● (list-ref planes 1) view))
                                         (TextureEntry 4 (● depth view))
                                         (TextureEntry 12 (● pong view))
                                         (TextureEntry 15 light)
                                         (BufferEntry 17 (● kit filtering) 0 256)))))))

    (define (release-targets (targets Targets)) (→ Unit) (! gpu)
      (for-each (lambda (group) (destroy (BindGroupObject group)))
                (Cons (● targets surface-group)
                      (Cons (● targets path-group)
                            (Cons (● targets remodulate-group)
                                  (concatenate (list (● targets temporal-groups)
                                                     (● targets variance-groups)
                                                     (● targets atrous-groups)))))))
      (for-each (lambda (plane)
                  (destroy (ViewObject (● plane view)))
                  (destroy (TextureObject (● plane texture))))
                (concatenate (list (list (● targets depth) (● targets noisy) (● targets integrated) (● targets ping) (● targets pong))
                                   (● targets planes)
                                   (● targets colors)
                                   (● targets moments)
                                   (● targets places)))))

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
                     (declarations filtering-shape)
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
