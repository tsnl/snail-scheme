;; Rasterizing batches of mesh instances, lit at once by the frame's sun
;; (raster.wgsl.scm): opaque batches first, then translucent ones blended
;; over them. A program makes its `Raster` once, its pipelines, its
;; geometry and its camera's and sun's uniforms, and a `Surface` for each
;; batch, remade when the batch changes. A frame of a low-poly scene:
;;
;;   (write-raster gpu r camera sun)
;;   (let ((pass ...))                ; a forward pass with a depth target
;;     (draw-surface gpu pass r terrain)
;;     (draw-surface gpu pass r water)
;;     (end-pass pass))
;;
;; The cameras and `Plane`, a texture and its view, are shared with the
;; forward renderer.
(define-library (snail shell graphics raster)
  (export
   Lens
   Pinhole
   PinholeRange
   Parallel
   Camera3D
   Camera3D-view-projection-set Camera3D-inverse-set
   Camera3D-scene-time-set
   camera-3d
   Style
   solid
   Sun
   Plane
   make-plane
   release-plane
   Raster
   make-forward-batches
   release-raster
   write-raster
   Surface
   make-surface
   restyle-surface
   release-surface
   draw-surface)
  (import
   (snail core base)
   (snail shell math)
   (snail shell wire)
   (snail shell gpu)
   (snail shell graphics pod)
   (snail shell graphics mesh)
   (snail shell graphics shaders))
  (begin

    ;; ---- Cameras ----

    ;; A perspective lens's vertical field of view in radians, or how many
    ;; world units a parallel one shows up the screen.
    (enum Lens
      (Pinhole ((fov F64)))
      (PinholeRange ((fov F64) (near F64) (far F64)))
      (Parallel ((height F64))))

    ;; The view-projection and its inverse, the eye with 1 in w for a
    ;; parallel lens, the direction it looks with the frame's motion in w,
    ;; and the scene's time. An upright sprite turns toward the camera.
    (record Camera3D
      ((view-projection Mat4x4f)
       (inverse Mat4x4f)
       (eye Vec4f)
       (forward Vec4f)
       (scene-time F32))
      (deriving Pod Serialize Deserialize))

    ;; Matrices here are 16 numbers, column by column.

    (define (camera-3d (eye Vec3f) (target Vec3f) (lens Lens) (aspect F64) (motion F32))
      (→ Camera3D)
      (let* ((e (vec eye))
             (forward (normalized (minus (vec target) e)))
             (projection (projected lens aspect (length-of (minus (vec target) e))))
             (view (look e forward))
             (vp (multiply (● projection first) (● view first)))
             (direction (new Vec4f (x (f64->f32 (list-ref forward 0)))
                             (y (f64->f32 (list-ref forward 1)))
                             (z (f64->f32 (list-ref forward 2)))
                             (w motion))))
        (new Camera3D
          (view-projection (matrix vp))
          (inverse (matrix (multiply (● view second) (● projection second))))
          (scene-time 0.0)
          (eye (new Vec4f
                 (x (● eye x))
                 (y (● eye y))
                 (z (● eye z))
                 (w (match lens ((Parallel _) 1.0) (_ 0.0)))))
          (forward direction))))

    ;; The view matrix and its inverse. Looking straight down, the top of
    ;; the screen is -z.
    (define (look (eye (List F64)) (forward (List F64))) (→ (Pair (List F64) (List F64)))
      (let* ((sky (if (> (abs (list-ref forward 1)) 0.999) (list 0.0 0.0 -1.0) (list 0.0 1.0 0.0)))
             (r (normalized (cross forward sky)))
             (u (cross r forward))
             (f forward))
        (new Pair
          (first (list (list-ref r 0) (list-ref u 0) (negate (list-ref f 0)) 0.0
                       (list-ref r 1) (list-ref u 1) (negate (list-ref f 1)) 0.0
                       (list-ref r 2) (list-ref u 2) (negate (list-ref f 2)) 0.0
                       (negate (dot r eye)) (negate (dot u eye)) (dot f eye) 1.0))
          (second (list (list-ref r 0) (list-ref r 1) (list-ref r 2) 0.0
                        (list-ref u 0) (list-ref u 1) (list-ref u 2) 0.0
                        (negate (list-ref f 0)) (negate (list-ref f 1)) (negate (list-ref f 2)) 0.0
                        (list-ref eye 0) (list-ref eye 1) (list-ref eye 2) 1.0)))))

    (define (perspective (fov F64) (aspect F64) (near F64) (far F64))
      (→ (Pair (List F64) (List F64)))
      (unless (and (> near 0.0) (> far near)) (panic "perspective needs 0 < near < far"))
      (let* ((f (/ 1.0 (tan (/ fov 2.0)))) (a (/ far (- near far))) (b (* near a)))
        (new Pair
          (first (list (/ f aspect) 0.0 0.0 0.0 0.0 f 0.0 0.0 0.0 0.0 a -1.0 0.0 0.0 b 0.0))
          (second (list (/ aspect f) 0.0 0.0 0.0 0.0 (/ 1.0 f) 0.0 0.0 0.0 0.0 0.0 (/ 1.0 b)
                        0.0 0.0 -1.0 (/ a b))))))

    ;; The projection and its inverse; depth runs from 0 at the near plane
    ;; to 1 at the far one, as WebGPU expects. A parallel lens sees from a
    ;; plane as far behind the eye as the target is ahead of it to four
    ;; times as far, so zooming never clips the ground.
    (define (projected (lens Lens) (aspect F64) (distance F64)) (→ (Pair (List F64) (List F64)))
      (match lens
        ((Pinhole fov) (perspective fov aspect 0.1 500.0))
        ((PinholeRange fov near far) (perspective fov aspect near far))
        ((Parallel height)
         (let* ((y (/ 2.0 height))
                (x (/ y aspect))
                (near (negate distance))
                (z (/ 1.0 (- near (* distance 4.0)))))
           (new Pair
             (first (list x 0.0 0.0 0.0 0.0 y 0.0 0.0 0.0 0.0 z 0.0 0.0 0.0 (* near z) 1.0))
             (second (list (/ 1.0 x)
                           0.0
                           0.0
                           0.0
                           0.0
                           (/ 1.0 y)
                           0.0
                           0.0
                           0.0
                           0.0
                           (/ 1.0 z)
                           0.0
                           0.0
                           0.0
                           (negate near)
                           1.0)))))))

    (define (multiply (a (List F64)) (b (List F64))) (→ (List F64))
      (map (lambda (index)
             (let ((column (quotient index 4)) (row (remainder index 4)))
               (fold-left (lambda (sum k)
                            (+ sum
                               (* (list-ref a (+ (* k 4) row)) (list-ref b (+ (* column 4) k)))))
                          0.0
                          (iota 4))))
           (iota 16)))

    (define (matrix (m (List F64))) (→ Mat4x4f)
      (let ((column (lambda (c)
                      (new Vec4f
                        (x (f64->f32 (list-ref m (* c 4))))
                        (y (f64->f32 (list-ref m (+ (* c 4) 1))))
                        (z (f64->f32 (list-ref m (+ (* c 4) 2))))
                        (w (f64->f32 (list-ref m (+ (* c 4) 3))))))))
        (new Mat4x4f (x (column 0)) (y (column 1)) (z (column 2)) (w (column 3)))))

    (define (vec (v Vec3f)) (→ (List F64))
      (list (f32->f64 (● v x)) (f32->f64 (● v y)) (f32->f64 (● v z))))

    (define (minus (a (List F64)) (b (List F64))) (→ (List F64))
      (map (lambda (i) (- (list-ref a i) (list-ref b i))) (iota 3)))

    (define (dot (a (List F64)) (b (List F64))) (→ F64)
      (fold-left (lambda (sum i) (+ sum (* (list-ref a i) (list-ref b i)))) 0.0 (iota 3)))

    (define (length-of (v (List F64))) (→ F64) (sqrt (dot v v)))

    (define (normalized (v (List F64))) (→ (List F64))
      (let ((l (length-of v))) (map (lambda (x) (/ x l)) v)))

    (define (cross (a (List F64)) (b (List F64))) (→ (List F64))
      (list (- (* (list-ref a 1) (list-ref b 2)) (* (list-ref a 2) (list-ref b 1)))
            (- (* (list-ref a 2) (list-ref b 0)) (* (list-ref a 0) (list-ref b 2)))
            (- (* (list-ref a 0) (list-ref b 1)) (* (list-ref a 1) (list-ref b 0)))))

    ;; ---- Styles and the sun ----

    ;; A batch's opacity, and the disc on the ground it shows within; a
    ;; negative radius shows it everywhere.
    (record Style
      ((opacity F32)
       (center-x F32)
       (center-z F32)
       (radius F32))
      (deriving Pod))

    (define solid (→ Style) (new Style (opacity 1.0) (center-x 0.0) (center-z 0.0) (radius -1.0)))

    ;; The direction toward the sun with its strength in w, and the light
    ;; every surface receives whichever way it faces.
    (record Sun
      ((direction Vec4f)
       (ambient F32))
      (deriving Pod))

    (define camera-shape (→ (Shape Camera3D)) (shape))
    (define style-shape (→ (Shape Style)) (shape))
    (define sun-shape (→ (Shape Sun)) (shape))

    (define raster-code
      (→ String)
      (string-append (declarations camera-shape)
                     (declarations style-shape)
                     (declarations sun-shape)
                     lighting-shader
                     raster-shader))

    ;; ---- Planes ----

    ;; A target and the view the passes draw to and read. The two are made
    ;; together and let go together, so no view outlives its texture.
    (record Plane
      ((texture GpuTexture)
       (view GpuTextureView)))

    (define (make-plane (gpu Gpu) (label String)
                        (width I32)
                        (height I32)
                        (format TextureFormat)
                        (usage (List TextureUsage)))
      (→ Plane)
      (let ((texture ((● gpu create-texture) (new TextureDescriptor
                                               (label label)
                                               (width (max 1 width))
                                               (height (max 1 height))
                                               (layers 1)
                                               (mips 1)
                                               (format format)
                                               (usage usage)))))
        (new Plane (texture texture) (view (view-of gpu texture 1)))))

    (define (release-plane (gpu Gpu) (plane Plane)) (→ Unit)
      ((● gpu destroy) (ViewObject (● plane view)))
      ((● gpu destroy) (TextureObject (● plane texture))))

    ;; ---- Pipelines and uniforms ----

    ;; The pipelines for opaque and for translucent surfaces on a target
    ;; of `format`, the meshes' geometry, and the camera's and sun's
    ;; uniforms with the bind groups that hold them. A pipeline's layout is
    ;; its own, so each pipeline has its own camera group.
    (record Raster
      ((opaque-pipeline GpuRenderPipeline)
       (forward-pipeline GpuRenderPipeline)
       (geometry MeshGeometry)
       (camera GpuBuffer)
       (sun GpuBuffer)
       (opaque-camera GpuBindGroup)
       (opaque-sun GpuBindGroup)
       (forward-camera GpuBindGroup)
       (forward-sun GpuBindGroup)))

    (define (make-forward-batches (gpu Gpu) (format TextureFormat)) (→ Raster)
      (let* ((module ((● gpu create-shader-module)
                      (new ShaderModuleDescriptor (label "raster") (code raster-code))))
             (opaque-pipeline (surface-pipeline gpu module "forward_fragment"
                                                (list (Some (new ColorTarget
                                                              (format format)
                                                              (blend (None)))))
                                                #t))
             (forward-pipeline (surface-pipeline gpu module
                                                 "forward_fragment"
                                                 (list (Some (new ColorTarget
                                                               (format format)
                                                               (blend (Some over)))))
                                                 #f))
             (camera (uniform gpu "raster/camera" (stride camera-shape)))
             (sun (uniform gpu "raster/sun" (stride sun-shape))))
        ((● gpu destroy) (ModuleObject module))
        (new Raster
          (opaque-pipeline opaque-pipeline)
          (forward-pipeline forward-pipeline)
          (geometry (make-geometry gpu))
          (camera camera)
          (sun sun)
          (opaque-camera (group gpu "raster/camera" opaque-pipeline 0 camera))
          (opaque-sun (group gpu "raster/sun" opaque-pipeline 2 sun))
          (forward-camera (group gpu "raster/forward/camera" forward-pipeline 0 camera))
          (forward-sun (group gpu "raster/sun" forward-pipeline 2 sun)))))

    (define (release-raster (gpu Gpu) (r Raster)) (→ Unit)
      (let ((drop (● gpu destroy)))
        (for-each drop
                  (list (BindGroupObject (● r opaque-camera)) (BindGroupObject (● r opaque-sun))
                        (BindGroupObject (● r forward-camera))
                        (BindGroupObject (● r forward-sun))
                        (PipelineObject (● r opaque-pipeline))
                        (PipelineObject (● r forward-pipeline))
                        (BufferObject (● r camera)) (BufferObject (● r sun))
                        (BufferObject (● r geometry vertices))
                        (BufferObject (● r geometry indices))))))

    ;; The frame's camera and its sun, written to the raster's uniforms.
    (define (write-raster (gpu Gpu) (r Raster) (camera Camera3D) (sun Sun)) (→ Unit)
      ((● gpu write-buffer) (● r camera) 0 (pod-bytes camera-shape camera))
      ((● gpu write-buffer) (● r sun) 0 (pod-bytes sun-shape sun)))

    (define (surface-pipeline (gpu Gpu) (module GpuShaderModule)
                              (entry String)
                              (targets (List (Option ColorTarget)))
                              (write? Bool))
      (→ GpuRenderPipeline)
      ((● gpu create-render-pipeline)
       (new RenderPipelineDescriptor
         (label (string-append "raster/" entry))
         (module module)
         (vertex-entry "surface_vertex")
         (buffers mesh-buffers)
         (fragment
          (Some (new FragmentState (entry entry) (targets targets))))
         (topology (TriangleList))
         (cull (CullNone))
         (depth
          (Some (new DepthState
                  (format (Depth24Plus))
                  (write write?)
                  (compare (CompareLess))))))))

    (define (uniform (gpu Gpu) (label String) (size I64)) (→ GpuBuffer)
      ((● gpu create-buffer) (new BufferDescriptor
                               (label label)
                               (size (i64->i32 size))
                               (usage (list (Uniform) (CopyDst))))))

    (define (group (gpu Gpu)
                   (label String)
                   (pipeline GpuRenderPipeline)
                   (index I32)
                   (buffer GpuBuffer))
      (→ GpuBindGroup)
      ((● gpu create-bind-group) (new BindGroupDescriptor
                                   (label label)
                                   (pipeline (RenderPipeline pipeline))
                                   (group index)
                                   (entries (list (BufferEntry 0 buffer 0 0))))))

    ;; ---- Surfaces ----

    ;; A batch of meshes drawn in one style: opaque, or, when translucent,
    ;; blended over what is drawn. Its style lives in a uniform of its
    ;; own, rewritten when it changes. Its objects are labelled "raster/"
    ;; and "mesh/" before its label.
    (record Surface
      ((translucent Bool)
       (style Style)
       (uniform GpuBuffer)
       (group GpuBindGroup)
       (batch MeshBatch)))

    (define (make-surface (gpu Gpu) (r Raster)
                          (label String)
                          (translucent Bool)
                          (style Style)
                          (batch Meshes))
      (→ Surface)
      (let ((buffer (uniform gpu (string-append "raster/" label) (stride style-shape))))
        ((● gpu write-buffer) buffer 0 (pod-bytes style-shape style))
        (new Surface
          (translucent translucent)
          (style style)
          (uniform buffer)
          (group (group gpu (string-append "raster/" label)
                        (if translucent (● r forward-pipeline) (● r opaque-pipeline))
                        1
                        buffer))
          (batch (upload-batch gpu (string-append "mesh/" label) batch)))))

    (define (restyle-surface (gpu Gpu) (surface Surface) (style Style)) (→ Surface)
      (if (same-style? style (● surface style))
          surface
          (begin
            ((● gpu write-buffer) (● surface uniform) 0 (pod-bytes style-shape style))
            (Surface-style-set surface style))))

    (define (same-style? (a Style) (b Style)) (→ Bool)
      (and (= (● a opacity) (● b opacity))
           (= (● a center-x) (● b center-x))
           (= (● a center-z) (● b center-z))
           (= (● a radius) (● b radius))))

    (define (release-surface (gpu Gpu) (surface Surface)) (→ Unit)
      ((● gpu destroy) (BindGroupObject (● surface group)))
      ((● gpu destroy) (BufferObject (● surface uniform)))
      (release-batch gpu (● surface batch)))

    (define (draw-surface (gpu Gpu) (pass GpuRenderPass) (r Raster) (surface Surface))
      (→ Unit)
      (if (● surface translucent)
          (begin
            ((● gpu set-pipeline) pass (● r forward-pipeline))
            ((● gpu set-bind-group) pass 0 (● r forward-camera))
            ((● gpu set-bind-group) pass 2 (● r forward-sun)))
          (begin
            ((● gpu set-pipeline) pass (● r opaque-pipeline))
            ((● gpu set-bind-group) pass 0 (● r opaque-camera))
            ((● gpu set-bind-group) pass 2 (● r opaque-sun))))
      ((● gpu set-bind-group) pass 1 (● surface group))
      (draw-meshes gpu pass (● r geometry) (● surface batch)))

    ))
