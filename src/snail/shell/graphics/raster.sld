;; Rasterizing mesh instances into a G-buffer, and translucent ones lit at
;; once over what is drawn (raster.wgsl.scm). A frame of a low-poly scene:
;;
;;   (let* ((g (gbuffer "scene" width height))
;;          (r (raster format camera sun))
;;          (pass (begin-gbuffer encoder g)))
;;     (raster-meshes pass r "terrain" solid terrain #t)
;;     (end-pass pass)
;;     (sun-pass encoder canvas format background g r)   ; (snail shell graphics passes)
;;     (let ((pass (begin-forward encoder canvas g)))
;;       (raster-translucent pass r "water" (Style ...) water #t)
;;       (end-pass pass)))
;;
;; The G-buffer holds each pixel's albedo, its normal, its material
;; (metalness, roughness and glow) and its depth. A frame makes its `Raster`
;; once: its pipelines, found by path, and its camera and sun, written to
;; uniform buffers.
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
   GBuffer
   gbuffer
   Raster
   raster
   begin-gbuffer
   raster-meshes
   begin-forward
   raster-translucent)
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
    ;; parallel lens, and the direction it looks with the frame's motion in
    ;; w.
    (record Camera3D
      ((view-projection Mat4x4f)
       (inverse Mat4x4f)
       (eye Vec4f)
       (forward Vec4f))
      (deriving Pod))

    ;; Matrices here are 16 numbers, column by column.

    (define (camera-3d (eye Vec3f) (target Vec3f) (lens Lens) (aspect F64) (motion F32))
      (→ Camera3D)
      (let* ((e (vec eye))
             (forward (normalized (minus (vec target) e)))
             (projection (projected lens aspect (length-of (minus (vec target) e))))
             (view (look e forward)))
        (new Camera3D
          (view-projection (matrix (multiply (● projection first) (● view first))))
          (inverse (matrix (multiply (● view second) (● projection second))))
          (eye (new Vec4f
                 (x (● eye x))
                 (y (● eye y))
                 (z (● eye z))
                 (w (match lens ((Pinhole _) 0.0) ((Parallel _) 1.0)))))
          (forward (new Vec4f
                     (x (f64->f32 (list-ref forward 0)))
                     (y (f64->f32 (list-ref forward 1)))
                     (z (f64->f32 (list-ref forward 2)))
                     (w motion))))))

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

    (record GBuffer
      ((albedo GpuTexture)
       (normal GpuTexture)
       (material GpuTexture)
       (depth GpuTexture)))

    (define (gbuffer (name String) (width I32) (height I32)) (→ GBuffer) (! gpu)
      (new GBuffer
        (albedo (target name "albedo" width height (Rgba8Unorm)))
        (normal (target name "normal" width height (Rgba16Float)))
        (material (target name "material" width height (Rgba8Unorm)))
        (depth (target name "depth" width height (Depth24Plus)))))

    (define (target (name String) (part String) (width I32) (height I32) (format TextureFormat))
      (→ GpuTexture)
      (! gpu)
      (create-texture (new TextureDescriptor
                        (path (Some (list "gbuffer" name part)))
                        (width width)
                        (height height)
                        (layers 1)
                        (mips 1)
                        (format format)
                        (usage (list (RenderAttachment) (TextureBinding))))))

    (define gbuffer-formats (→ (List TextureFormat)) (list (Rgba8Unorm) (Rgba16Float) (Rgba8Unorm)))

    (define (begin-gbuffer (encoder GpuCommandEncoder) (g GBuffer)) (→ GpuRenderPass) (! gpu)
      (begin-render-pass encoder
                         (new RenderPassDescriptor
                           (colors (map (lambda (texture)
                                          (new ColorAttachment
                                            (view (view-of texture 1))
                                            (load (Clear (new Color
                                                           (red 0.0)
                                                           (green 0.0)
                                                           (blue 0.0)
                                                           (alpha 0.0))))
                                            (store #t)))
                                        (list (● g albedo) (● g normal) (● g material))))
                           (depth (Some (new DepthAttachment
                                          (view (view-of (● g depth) 1))
                                          (load (ClearDepth 1.0))
                                          (store #t)))))))

    ;; A pass over `canvas` keeping what is drawn, testing against the
    ;; G-buffer's depth without writing it.
    (define (begin-forward (encoder GpuCommandEncoder) (canvas GpuTexture) (g GBuffer))
      (→ GpuRenderPass)
      (! gpu)
      (begin-render-pass encoder
                         (new RenderPassDescriptor
                           (colors (list (new ColorAttachment
                                           (view (view-of canvas 1))
                                           (load (Keep))
                                           (store #t))))
                           (depth (Some (new DepthAttachment
                                          (view (view-of (● g depth) 1))
                                          (load (KeepDepth))
                                          (store #t)))))))

    ;; ---- Drawing ----

    ;; A frame's pipelines for the G-buffer and for translucent surfaces
    ;; on a target of `format`, and its camera and sun.
    (record Raster
      ((gbuffer-pipeline GpuRenderPipeline)
       (forward-pipeline GpuRenderPipeline)
       (camera GpuBuffer)
       (sun GpuBuffer)))

    (define (raster (format TextureFormat) (camera Camera3D) (sun Sun)) (→ Raster) (! gpu)
      (new Raster
        (gbuffer-pipeline (surface-pipeline "gbuffer_fragment"
                                            (map (lambda (format)
                                                   (new ColorTarget (format format) (blend (None))))
                                                 gbuffer-formats)
                                            #t))
        (forward-pipeline (surface-pipeline "forward_fragment"
                                            (list
                                             (new ColorTarget (format format) (blend (Some over))))
                                            #f))
        (camera (uniform (list "raster" "camera") (pod-bytes camera-shape camera)))
        (sun (uniform (list "raster" "sun") (pod-bytes sun-shape sun)))))

    (define (raster-meshes (pass GpuRenderPass)
                           (r Raster)
                           (name String)
                           (style Style)
                           (batch Meshes)
                           (write? Bool))
      (→ Unit)
      (! gpu)
      (let ((pipeline (● r gbuffer-pipeline)))
        (set-pipeline pass pipeline)
        (set-bind-group pass 0 (group (list "raster" "camera") pipeline 0 (● r camera)))
        (set-bind-group pass
                        1
                        (group (list "raster" name)
                               pipeline
                               1
                               (uniform (list "raster" name) (pod-bytes style-shape style))))
        (draw-meshes pass name batch write?)))

    (define (raster-translucent (pass GpuRenderPass)
                                (r Raster)
                                (name String)
                                (style Style)
                                (batch Meshes)
                                (write? Bool))
      (→ Unit)
      (! gpu)
      (let ((pipeline (● r forward-pipeline)))
        (set-pipeline pass pipeline)
        (set-bind-group pass 0 (group (list "raster" "forward" "camera") pipeline 0 (● r camera)))
        (set-bind-group pass
                        1
                        (group (list "raster" "forward" name)
                               pipeline
                               1
                               (uniform (list "raster" name) (pod-bytes style-shape style))))
        (set-bind-group pass 2 (group (list "raster" "sun") pipeline 2 (● r sun)))
        (draw-meshes pass name batch write?)))

    (define (surface-pipeline (entry String) (targets (List ColorTarget)) (write? Bool))
      (→ GpuRenderPipeline)
      (! gpu)
      (create-render-pipeline
       (new RenderPipelineDescriptor
         (path (Some (Cons "raster"
                           (Cons entry
                                 (map (lambda (target) (texture-format-name (● target format)))
                                      targets)))))
         (module (create-shader-module
                  (new ShaderModuleDescriptor
                    (path (Some (list "raster" "shader")))
                    (code raster-code))))
         (vertex-entry "surface_vertex")
         (buffers mesh-buffers)
         (fragment (Some (new FragmentState (entry entry) (targets targets))))
         (topology (TriangleList))
         (cull (CullNone))
         (depth
          (Some (new DepthState (format (Depth24Plus)) (write write?) (compare (CompareLess))))))))

    ;; A uniform buffer by its path, holding `bytes`.
    (define (uniform (path (List String)) (bytes Bytes)) (→ GpuBuffer) (! gpu)
      (let ((buffer (create-buffer (new BufferDescriptor
                                     (path (Some path))
                                     (size (i64->i32 (array-length bytes)))
                                     (usage (list (Uniform) (CopyDst)))))))
        (write-buffer buffer 0 bytes)
        buffer))

    (define (group (path (List String)) (pipeline GpuRenderPipeline) (index I32) (buffer GpuBuffer))
      (→ GpuBindGroup)
      (! gpu)
      (create-bind-group (new BindGroupDescriptor
                           (path (Some path))
                           (pipeline pipeline)
                           (group index)
                           (entries (list (BufferEntry 0 buffer 0 0))))))

    ))
