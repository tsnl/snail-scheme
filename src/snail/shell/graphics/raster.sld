;; Rasterizing mesh instances into a G-buffer, and translucent ones lit at
;; once over the lit G-buffer (raster.wgsl.scm). A program makes its `Raster`
;; once, its pipelines, its geometry and its camera's and sun's uniforms;
;; a `GBuffer` for the canvas's size; and a `Surface` for each batch,
;; remade when the batch changes. A frame of a low-poly scene:
;;
;;   (let ((r (write-raster r camera sun))) ...)
;;   (let ((pass (begin-gbuffer encoder g)))
;;     (draw-surface pass r terrain)
;;     (end-pass pass))
;;   (let ((pass (begin-lit encoder canvas background g)))
;;     (draw-sun pass light)                       ; (snail shell graphics passes)
;;     (draw-surface pass r water)
;;     (end-pass pass))
;;
;; The G-buffer holds each pixel's albedo, its normal, its material
;; (metalness, roughness and glow) and its depth, and, when its `Planes`
;; ask, its motion since the last frame and the id of the instance drawn
;; there. The `Raster` and the `GBuffer` are made for the same `Planes`.
;; `read-id` reads one pixel's id back, to pick what a tap is on.
(define-library (snail shell graphics raster)
  (export
   Lens
   Pinhole
   Parallel
   Camera3D
   camera-3d
   Style
   solid
   Sun
   Planes
   color-planes
   Plane
   make-plane
   release-plane
   GBuffer
   make-gbuffer
   read-id
   release-gbuffer
   Raster
   make-raster
   write-raster
   begin-gbuffer
   begin-lit
   Surface
   make-surface
   restyle-surface
   release-surface
   draw-surface)
  (import
   (snail core base)
   (snail shell math)
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
      (Parallel ((height F64))))

    ;; The view-projection and its inverse, the eye with 1 in w for a
    ;; parallel lens, the direction it looks with the frame's motion in w,
    ;; and the last frame's view-projection, motion and horizontal viewing
    ;; direction. An upright sprite turns toward each frame's camera.
    (record Camera3D
      ((view-projection Mat4x4f)
       (inverse Mat4x4f)
       (eye Vec4f)
       (forward Vec4f)
       (previous Mat4x4f)
       (previous-motion F32)
       (previous-heading Vec2f))
      (deriving Pod))

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
          (previous (matrix vp))
          (previous-motion motion)
          (previous-heading (horizontal-direction direction))
          (eye (new Vec4f
                 (x (● eye x))
                 (y (● eye y))
                 (z (● eye z))
                 (w (match lens ((Pinhole _) 0.0) ((Parallel _) 1.0)))))
          (forward direction))))

    (define (horizontal-direction (direction Vec4f)) (→ Vec2f)
      (new Vec2f (x (● direction x)) (y (● direction z))))

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

    ;; The projection and its inverse; depth runs from 0 at the near plane
    ;; to 1 at the far one, as WebGPU expects. A parallel lens sees from a
    ;; plane as far behind the eye as the target is ahead of it to four
    ;; times as far, so zooming never clips the ground.
    (define (projected (lens Lens) (aspect F64) (distance F64)) (→ (Pair (List F64) (List F64)))
      (match lens
        ((Pinhole fov)
         (let* ((f (/ 1.0 (tan (/ fov 2.0))))
                (near 0.1)
                (far 500.0)
                (a (/ far (- near far)))
                (b (/ (* near far) (- near far))))
           (new Pair
             (first (list (/ f aspect) 0.0 0.0 0.0 0.0 f 0.0 0.0 0.0 0.0 a -1.0 0.0 0.0 b 0.0))
             (second (list (/ aspect f)
                           0.0
                           0.0
                           0.0
                           0.0
                           (/ 1.0 f)
                           0.0
                           0.0
                           0.0
                           0.0
                           0.0
                           (/ 1.0 b)
                           0.0
                           0.0
                           -1.0
                           (/ a b))))))
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

    ;; ---- The G-buffer ----

    ;; The planes beyond albedo, normal, material and depth: the screen
    ;; motion, in texture coordinates, from where each pixel's surface was
    ;; in the last frame, and the id of its instance, 0 where there is none.
    (record Planes
      ((motion Bool)
       (ids Bool)))

    (define color-planes (→ Planes) (new Planes (motion #f) (ids #f)))

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
      (let ((texture (gpu::create-texture (new TextureDescriptor
                                            (label label)
                                            (width (max 1 width))
                                            (height (max 1 height))
                                            (layers 1)
                                            (mips 1)
                                            (format format)
                                            (usage usage)))))
        (new Plane (texture texture) (view (view-of gpu texture 1)))))

    (define (release-plane (gpu Gpu) (plane Plane)) (→ Unit)
      (gpu::destroy (ViewObject (● plane view)))
      (gpu::destroy (TextureObject (● plane texture))))

    (record GBuffer
      ((albedo Plane)
       (normal Plane)
       (material Plane)
       (depth Plane)
       (motion (Option Plane))
       (ids (Option Plane))))

    (define (make-gbuffer (gpu Gpu) (planes Planes) (width I32) (height I32)) (→ GBuffer)
      (let ((size (new Pair (first width) (second height))))
        (new GBuffer
          (albedo (gbuffer-plane gpu "albedo" size (Rgba8Unorm)))
          (normal (gbuffer-plane gpu "normal" size (Rgba16Float)))
          (material (gbuffer-plane gpu "material" size (Rgba8Unorm)))
          (depth (gbuffer-plane gpu "depth" size (Depth24Plus)))
          (motion
           (if (● planes motion) (Some (gbuffer-plane gpu "motion" size (Rg16Float))) (None)))
          (ids (if (● planes ids) (Some (gbuffer-plane gpu "ids" size (R32Uint))) (None))))))

    (define (release-gbuffer (gpu Gpu) (g GBuffer)) (→ Unit)
      (for-each (lambda (plane) (release-plane gpu plane))
                (append (list (● g albedo) (● g normal) (● g material) (● g depth))
                        (present (list (● g motion) (● g ids))))))

    (define (present (planes (List (Option Plane)))) (→ (List Plane))
      (fold-right (lambda (plane rest)
                    (match plane
                      ((Some plane) (Cons plane rest))
                      ((None) rest)))
                  (Nil)
                  planes))

    (define (gbuffer-plane (gpu Gpu) (part String) (size (Pair I32 I32)) (format TextureFormat))
      (→ Plane)
      (make-plane gpu (string-append "gbuffer/" part)
                  (● size first)
                  (● size second)
                  format
                  (list (RenderAttachment) (TextureBinding) (TextureCopySrc))))

    ;; A target for each color plane, None where `planes` leaves one out:
    ;; the G-buffer pass's attachments have the same gaps.
    (define (gbuffer-targets (planes Planes)) (→ (List (Option ColorTarget)))
      (map (lambda (format)
             (match format
               ((Some format) (Some (new ColorTarget (format format) (blend (None)))))
               ((None) (None))))
           (list (Some (Rgba8Unorm))
                 (Some (Rgba16Float))
                 (Some (Rgba8Unorm))
                 (if (● planes motion) (Some (Rg16Float)) (None))
                 (if (● planes ids) (Some (R32Uint)) (None)))))

    ;; The id of the instance at pixel `x`, `y`, when the G-buffer has ids.
    (define (read-id (gpu Gpu) (g GBuffer) (x I32) (y I32)) (→ (Option I32))
      (match (● g ids)
        ((Some plane) (Some (texel-word gpu (● plane texture) x y)))
        ((None) (None))))

    (define (texel-word (gpu Gpu) (texture GpuTexture) (x I32) (y I32)) (→ I32)
      (let ((readback (gpu::create-buffer (new BufferDescriptor
                                            (label "gbuffer/read-id")
                                            (size 4)
                                            (usage (list (MapRead) (CopyDst))))))
            (encoder (gpu::create-command-encoder)))
        (gpu::copy-texture-to-buffer encoder
                                     (new TextureCopy
                                       (texture texture)
                                       (mip 0)
                                       (x x)
                                       (y y)
                                       (layer 0))
                                     readback 0 256 1 1)
        (gpu::submit (list (gpu::finish encoder)))
        (let ((bytes (gpu::read-buffer readback 0 4)))
          (gpu::destroy (BufferObject readback))
          (fold-right (lambda (byte word) (+ (u8->i32 byte) (* word 256))) 0 (array->list bytes)))))

    (define (begin-gbuffer (gpu Gpu) (encoder GpuCommandEncoder) (g GBuffer))
      (→ GpuRenderPass)
      (gpu::begin-render-pass encoder
                              (new RenderPassDescriptor
                                (colors (map (lambda (plane)
                                               (match plane
                                                 ((Some plane)
                                                  (Some (new ColorAttachment
                                                          (view (● plane view))
                                                          (load (Clear (new Color
                                                                         (red 0.0)
                                                                         (green 0.0)
                                                                         (blue 0.0)
                                                                         (alpha 0.0))))
                                                          (store #t))))
                                                 ((None) (None))))
                                             (list (Some (● g albedo))
                                                   (Some (● g normal))
                                                   (Some (● g material))
                                                   (● g motion)
                                                   (● g ids))))
                                (depth (Some (new DepthAttachment
                                               (view (● g depth view))
                                               (load (ClearDepth 1.0))
                                               (store #t)))))))

    ;; A pass over `canvas`, cleared to `background`, that reads the
    ;; G-buffer's depth without writing it: the sun lights the G-buffer
    ;; into it, sampling that depth, and translucent surfaces are drawn
    ;; over, tested against it.
    (define (begin-lit (gpu Gpu) (encoder GpuCommandEncoder)
                       (canvas GpuTextureView)
                       (background Color)
                       (g GBuffer))
      (→ GpuRenderPass)
      (gpu::begin-render-pass encoder
                              (new RenderPassDescriptor
                                (colors (list (Some (new ColorAttachment
                                                      (view canvas)
                                                      (load (Clear background))
                                                      (store #t)))))
                                (depth (Some (new DepthAttachment
                                               (view (● g depth view))
                                               (load (ReadOnlyDepth))
                                               (store #f)))))))

    ;; ---- Pipelines and uniforms ----

    ;; The pipelines for the G-buffer's planes and for translucent surfaces
    ;; on a target of `format`, the meshes' geometry, the camera's and sun's
    ;; uniforms with the bind groups that hold them, and the last frame's
    ;; camera. A pipeline's layout is its own, so each pipeline has its own
    ;; camera group.
    (record Raster
      ((gbuffer-pipeline GpuRenderPipeline)
       (forward-pipeline GpuRenderPipeline)
       (geometry MeshGeometry)
       (camera GpuBuffer)
       (sun GpuBuffer)
       (gbuffer-camera GpuBindGroup)
       (forward-camera GpuBindGroup)
       (forward-sun GpuBindGroup)
       (last (Option Camera3D))))

    (define (make-raster (gpu Gpu) (planes Planes) (format TextureFormat)) (→ Raster)
      (let* ((module (gpu::create-shader-module
                      (new ShaderModuleDescriptor
                        (label "raster")
                        (code raster-code))))
             (gbuffer-pipeline (surface-pipeline gpu module
                                                 "gbuffer_fragment"
                                                 (gbuffer-targets planes)
                                                 #t))
             (forward-pipeline (surface-pipeline gpu module
                                                 "forward_fragment"
                                                 (list (Some (new ColorTarget
                                                               (format format)
                                                               (blend (Some over)))))
                                                 #f))
             (camera (uniform gpu "raster/camera" (stride camera-shape)))
             (sun (uniform gpu "raster/sun" (stride sun-shape))))
        (new Raster
          (gbuffer-pipeline gbuffer-pipeline)
          (forward-pipeline forward-pipeline)
          (geometry (make-geometry gpu))
          (camera camera)
          (sun sun)
          (gbuffer-camera (group gpu "raster/camera" gbuffer-pipeline 0 camera))
          (forward-camera (group gpu "raster/forward/camera" forward-pipeline 0 camera))
          (forward-sun (group gpu "raster/sun" forward-pipeline 2 sun))
          (last (None)))))

    ;; The frame's camera, moving from the last frame's, and its sun. A
    ;; batch remade since the last frame shows the motion of its new
    ;; instances.
    (define (write-raster (gpu Gpu) (r Raster) (camera Camera3D) (sun Sun)) (→ Raster)
      (let ((camera (match (● r last)
                      ((Some last)
                       (Camera3D-previous-heading-set
                        (Camera3D-previous-motion-set
                         (Camera3D-previous-set camera (● last view-projection))
                         (● last forward w))
                        (horizontal-direction (● last forward))))
                      ((None) camera))))
        (gpu::write-buffer (● r camera) 0 (pod-bytes camera-shape camera))
        (gpu::write-buffer (● r sun) 0 (pod-bytes sun-shape sun))
        (Raster-last-set r (Some camera))))

    (define (surface-pipeline (gpu Gpu) (module GpuShaderModule)
                              (entry String)
                              (targets (List (Option ColorTarget)))
                              (write? Bool))
      (→ GpuRenderPipeline)
      (gpu::create-render-pipeline
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
      (gpu::create-buffer (new BufferDescriptor
                            (label label)
                            (size (i64->i32 size))
                            (usage (list (Uniform) (CopyDst))))))

    (define (group (gpu Gpu)
                   (label String)
                   (pipeline GpuRenderPipeline)
                   (index I32)
                   (buffer GpuBuffer))
      (→ GpuBindGroup)
      (gpu::create-bind-group (new BindGroupDescriptor
                                (label label)
                                (pipeline (RenderPipeline pipeline))
                                (group index)
                                (entries (list (BufferEntry 0 buffer 0 0))))))

    ;; ---- Surfaces ----

    ;; A batch of meshes drawn in one style: into the G-buffer, or, when
    ;; translucent, over what is drawn. Its style lives in a uniform of its
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
        (gpu::write-buffer buffer 0 (pod-bytes style-shape style))
        (new Surface
          (translucent translucent)
          (style style)
          (uniform buffer)
          (group (group gpu (string-append "raster/" label)
                        (if translucent (● r forward-pipeline) (● r gbuffer-pipeline))
                        1
                        buffer))
          (batch (upload-batch gpu (string-append "mesh/" label) batch)))))

    (define (restyle-surface (gpu Gpu) (surface Surface) (style Style)) (→ Surface)
      (if (same-style? style (● surface style))
          surface
          (begin
            (gpu::write-buffer (● surface uniform) 0 (pod-bytes style-shape style))
            (Surface-style-set surface style))))

    (define (same-style? (a Style) (b Style)) (→ Bool)
      (and (= (● a opacity) (● b opacity))
           (= (● a center-x) (● b center-x))
           (= (● a center-z) (● b center-z))
           (= (● a radius) (● b radius))))

    (define (release-surface (gpu Gpu) (surface Surface)) (→ Unit)
      (gpu::destroy (BindGroupObject (● surface group)))
      (gpu::destroy (BufferObject (● surface uniform)))
      (release-batch gpu (● surface batch)))

    (define (draw-surface (gpu Gpu) (pass GpuRenderPass) (r Raster) (surface Surface))
      (→ Unit)
      (if (● surface translucent)
          (begin
            (gpu::set-pipeline pass (● r forward-pipeline))
            (gpu::set-bind-group pass 0 (● r forward-camera))
            (gpu::set-bind-group pass 2 (● r forward-sun)))
          (begin
            (gpu::set-pipeline pass (● r gbuffer-pipeline))
            (gpu::set-bind-group pass 0 (● r gbuffer-camera))))
      (gpu::set-bind-group pass 1 (● surface group))
      (draw-meshes gpu pass (● r geometry) (● surface batch)))

    ))
