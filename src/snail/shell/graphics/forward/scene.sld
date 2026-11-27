;; The native vertex and index buffers, texture maps and draw ranges of a glTF scene.
(define-library (snail shell graphics forward scene)
  (export Scene MapImage DrawRange SurfaceMaterial material-shape surface-material
          upload-scene
          read-model-file
          load-scene
          release-scene
          vertex-stride
          configure-ground-layer!
          SkinLayout
          pack-skin
          skin-with-layout
          load-scene-images
          upload-with-images
          release-scene-images
          SceneImages
          MovingScene skin-scene deform-scene! release-moving-scene
          ObjectPose pose-matrix moving-scene)
  (import
   (snail core base)
   (snail shell gpu)
   (only (snail shell little-endian) u32)
   (snail shell graphics pod)
   (snail shell graphics gltf)
   (snail shell graphics kernel)
   (only (snail shell graphics animation)
         Influence
         SkinBinding
         rigid-binding
         shift-influence
         v4
         matrix-from product-column plus times)
   (only (snail shell graphics raster) Plane make-plane release-plane)
   (snail shell graphics compositor)
   (snail shell graphics forward lights)
   (snail shell graphics forward convex)
   (snail shell graphics forward shaders))
  (begin
    (record DrawRange
      ((first I32)
       (count I32)
       (material I64)
       (center Vec3f)))
    ;; Only transparent vertices need CPU bind positions for a moving sort key.
    (record BlendMesh
      ((draw DrawRange)
       (first-vertex I64)
       (points (Array Vec4f))))
    (record BlendPose
      ((draw DrawRange)
       (joints (List (Pair I64 Vec4f)))))
    (record MapImage
      ((texture GpuTexture)
       (view GpuTextureView)))
    (record SceneImages
      ((maps (Array MapImage))
       (sampler GpuSampler)))
    (record Scene
      ((vertices GpuBuffer)
       (indices GpuBuffer)
       (vertex-count I64)
       (materials (List Material))
       (images SceneImages)
       (owns-images Bool)
       (lights LightGrid)
       (local-lights Bool)
       (draws (List DrawRange))
       (blend-meshes (List BlendMesh))
       (low (List F64))
       (high (List F64))
       (ground-layer Plane)
       (ground-frame GpuBuffer)))
    (define vertex-stride (→ I64) 48)
    (define (draw-ranges (gltf Gltf) (default-material I64)) (→ (List DrawRange))
      (let loop ((items (● gltf placed)) (first 0) (draws (ann (Nil) (List DrawRange))))
        (match items
          ((Nil) (reverse draws))
          ((Cons p more)
           (let* ((prim (● p primitive)) (n (index-count prim)) (c (placed-center p)))
             (loop more (+ first n)
                   (Cons (new DrawRange (first (i64->i32 first)) (count (i64->i32 n))
                              (material
                               (if (< (● prim material) 0) default-material (● prim material)))
                              (center (new Vec3f (x (f64->f32 (list-ref c 0)))
                                           (y (f64->f32 (list-ref c 1)))
                                           (z (f64->f32 (list-ref c 2))))))
                         draws)))))))
    (define (bind-points (p Placed) (buffers (List (Pair Buffer Bytes)))) (→ (Array Vec4f))
      (let* ((a (● p primitive positions)) (matrix (matrix-from (● p matrix)))
             (b (find (lambda (entry)
                        (let ((start (● entry first start)))
                          (and (<= start (● a offset))
                               (< (● a offset) (+ start (● entry first length))))))
                      buffers)))
        (match b
          ((None) (unreadable "missing transparent vertex buffer"))
          ((Some entry)
           (array-generate (● a count)
                           (lambda (i)
                             (let ((v (position-at (● entry second) (● entry first start) a i)))
                               (product-column matrix
                                               (v4 (f64->f32 (list-ref v 0))
                                                   (f64->f32 (list-ref v 1))
                                                   (f64->f32 (list-ref v 2))
                                                   1.0)))))))))
    (define (blend-meshes (g Gltf)
                          (buffers (List Bytes))
                          (mats (Array Material))
                          (draws (List DrawRange)))
      (→ (List BlendMesh))
      (let ((sources (zip (● g buffers) buffers)))
        (let loop ((items (zip (● g placed) draws))
                   (vertex 0)
                   (meshes (ann (Nil) (List BlendMesh))))
          (match items ((Nil) (reverse meshes))
                 ((Cons entry more)
                  (let ((p (● entry first)) (r (● entry second)))
                    (loop more (+ vertex (● p primitive positions count))
                          (if (blended-material? (● (array-ref mats (● r material)) alpha))
                              (Cons (new BlendMesh
                                      (draw r)
                                      (first-vertex vertex)
                                      (points (bind-points p sources)))
                                    meshes)
                              meshes))))))))
    (record SurfaceMaterial
      ((base-color Vec4f)
       (emissive Vec4f)
       (factors Vec4f)
       (textures Vec4i)
       (flags Vec4i)
       (optics Vec4f))
      (deriving Pod))

    (define material-shape (→ (Shape SurfaceMaterial)) (shape))

    (define (load-scene (gpu Gpu) (read (Fn (List String) → (List Bytes))) (path String)) (→ Scene)
      (upload-scene gpu read (drawable (read-model-file read path))))
    (define (read-model-file (read (Fn (List String) → (List Bytes))) (path String)) (→ Gltf)
      (read-gltf (list-ref (read (list path)) 0) (directory-of path)))
    (define (upload-scene (gpu Gpu) (read (Fn (List String) → (List Bytes))) (gltf Gltf)) (→ Scene)
      (let* ((files (scene-files read (file-paths gltf))) (buffers (model-buffers gltf files))
             (materials (checked-materials gltf buffers))
             (images (model-images gpu gltf files buffers)))
        (upload-geometry gpu gltf buffers materials images #t (Nil) 0)))

    (define (scene-files (read (Fn (List String) → (List Bytes))) (paths (List String)))
      (→ (List (Pair String Bytes)))
      (zip paths (read paths)))
    (define (model-buffers (g Gltf) (files (List (Pair String Bytes)))) (→ (List Bytes))
      (map (lambda (b) (buffer-bytes b files)) (● g buffers)))
    (define (model-images (gpu Gpu)
                          (g Gltf)
                          (files (List (Pair String Bytes)))
                          (buffers (List Bytes)))
      (→ SceneImages)
      (new SceneImages
        (maps (scene-maps gpu (map (lambda (im) (source-bytes im files buffers)) (● g images))))
        (sampler (repeating-sampler gpu))))
    ;; For windows of the same world, the caller owns one image table for all
    ;; windows. Their geometry retains the same image indices across swaps.
    (define (load-scene-images (gpu Gpu) (read (Fn (List String) → (List Bytes))) (g Gltf))
      (→ SceneImages)
      (let ((files (scene-files read (file-paths g))))
        (model-images gpu g files (model-buffers g files))))
    (define (upload-with-images (gpu Gpu) (read (Fn (List String) → (List Bytes))) (g Gltf)
                                (images SceneImages) (lights (List Punctual)) (capacity I64))
      (→ Scene)
      (unless (= (+ 1 (length (● g images))) (array-length (● images maps)))
        (unreadable "scene image table mismatch"))
      (let ((files (scene-files read (source-paths (map (lambda (b) (● b source)) (● g buffers))))))
        (let ((buffers (model-buffers g files)))
          (upload-geometry gpu g buffers (checked-materials g buffers) images #f lights capacity))))

    (define (checked-materials (g Gltf) (buffers (List Bytes))) (→ (List Material))
      (when (null? (● g placed)) (unreadable "the scene has no triangles"))
      (let ((materials (drawable-materials g)))
        (check-transparent-meshes g buffers materials)
        materials))

    (define (upload-geometry (gpu Gpu)
                             (gltf Gltf)
                             (buffers (List Bytes))
                             (materials (List Material))
                             (images SceneImages)
                             (owns Bool)
                             (lights (List Punctual)) (capacity I64)) (→ Scene)
                             (let* ((counts (placed-counts gltf))
                                    (draws (draw-ranges gltf (- (length materials) 1)))
                                    (meshes
                                     (blend-meshes gltf buffers (list->array materials) draws))
                                    (geometry (unpacked gpu gltf counts buffers))
                                    (bounds (gltf-bounds gltf)))
                               (new Scene
                                 (vertices (● geometry first))
                                 (indices (● geometry second))
                                 (vertex-count (● counts first))
                                 (draws draws) (blend-meshes meshes)
                                 (materials materials)
                                 (images images)
                                 (owns-images owns)
                                 (lights (light-grid gpu lights capacity))
                                 (local-lights (or (> capacity 0) (not (null? lights))))
                                 (low (● bounds first))
                                 (high (● bounds second))
                                 (ground-layer (make-plane gpu
                                                           "scene/ground"
                                                           1
                                                           1
                                                           (Rgba8Unorm)
                                                           (list (TextureBinding))))
                                 (ground-frame (uniform-buffer gpu
                                                               "scene/ground-frame"
                                                               (make-array 16 (i32->u8 0)))))))
    (define (release-scene-images (gpu Gpu) (images SceneImages)) (→ Unit)
      (for-each (lambda (map) ((● gpu destroy) (ViewObject (● map view)))
                        ((● gpu destroy) (TextureObject (● map texture))))
                (array->list (● images maps)))
      ((● gpu destroy) (SamplerObject (● images sampler))))
    (define (release-scene (gpu Gpu) (scene Scene)) (→ Unit)
      (when (● scene owns-images) (release-scene-images gpu (● scene images)))
      (release-plane gpu (● scene lights plane))
      (release-plane gpu (● scene ground-layer))
      (for-each (lambda (buf) ((● gpu destroy) (BufferObject buf)))
                (list (● scene vertices) (● scene indices) (● scene ground-frame))))
    ;; Configure before binding the renderer. RG encodes signed X/Z normal detail,
    ;; B standing water, A compacted/damp soil. A zero texel is untouched ground.
    (define (configure-ground-layer! (gpu Gpu) (scene Scene) (w I32) (h I32) (frame Vec4f))
      (→ Plane)
      (let ((plane (make-plane gpu "scene/ground-field" w h (Rgba8Unorm)
                               (list (TextureBinding) (StorageBinding)))))
        (release-plane gpu (● scene ground-layer))
        (set! (● scene ground-layer) plane)
        ((● gpu write-buffer)
         (● scene ground-frame)
         0
         (pod-bytes (ann (shape) (Shape Vec4f)) frame))
        plane))
    ;; ---- Moving geometry ----

    ;; Position and cosine of yaw, then positive scale and sine of yaw.
    (record ObjectPose
      ((place Vec4f)
       (size Vec4f))
      (deriving Pod))

    (record MovingScene
      ((scene Scene)
       (rest GpuBuffer)
       (influences GpuBuffer)
       (poses GpuBuffer)
       (pipeline GpuComputePipeline)
       (group GpuBindGroup)
       (joints I64)
       (centers (List BlendPose))
       (vertices I64)))

    (define matrix-shape (→ (Shape Mat4x4f)) (shape))
    (define influence-shape (→ (Shape Influence)) (shape))
    (define (pose-matrix (pose ObjectPose)) (→ Mat4x4f)
      (let* ((p (● pose place)) (s (● pose size)) (c (● p w)) (a (● s w)))
        (new Mat4x4f
          (x (v4 (* c (● s x)) 0.0 (negate (* a (● s x))) 0.0))
          (y (v4 0.0 (● s y) 0.0 0.0))
          (z (v4 (* a (● s z)) 0.0 (* c (● s z)) 0.0)) (w (v4 (● p x) (● p y) (● p z) 1.0)))))

    ;; A rigid range is the one-joint case of linear blend skinning.
    (define (moving-scene (gpu Gpu) (source Scene) (counts (List I64))) (→ MovingScene)
      (skin-scene gpu source (map rigid-binding counts)))

    (define (bound-influence? (v Influence) (slots I64)) (→ Bool)
      (let ((j (● v joints)) (w (● v weights)))
        (and (>= (min (min (● j x) (● j y)) (min (● j z) (● j w))) 0)
             (< (i32->i64 (max (max (● j x) (● j y)) (max (● j z) (● j w)))) slots)
             (>= (min (min (● w x) (● w y)) (min (● w z) (● w w))) 0.0)
             (< (abs (- (+ (+ (● w x) (● w y)) (+ (● w z) (● w w))) 1.0)) 0.0001))))
    ;; Assign palette slots in instance order once, when the stage is built.
    (define (combined-binding (skins (List SkinBinding))) (→ SkinBinding)
      (let loop ((rest skins) (base 0) (ranges (Nil)))
        (match rest
          ((Nil) (new SkinBinding (slots base) (vertices (concatenate (reverse ranges)))))
          ((Cons skin next)
           (let ((n (● skin slots)) (vertices (● skin vertices)))
             (unless (and (> n 0)
                          (not (null? vertices))
                          (every? (lambda (v) (bound-influence? v n)) vertices))
               (panic "invalid vertex influence"))
             (loop next
                   (+ base n)
                   (Cons (map (lambda (v) (shift-influence v (i64->i32 base))) vertices)
                         ranges)))))))

    ;; Static vertices precede the influenced suffix. Own the original scene
    ;; as the immutable bind mesh and keep its topology and material bindings.
    (define (skin-scene (gpu Gpu) (source Scene) (bindings (List SkinBinding))) (→ MovingScene)
      (skin-with-layout gpu source (pack-skin bindings)))

    ;; Packing the same cast of actors once avoids traversing all their vertex
    ;; influences whenever only the static prefix of the world changes.
    (record SkinLayout
      ((bytes Bytes)
       (joints I64)
       (vertices I64)))
    (define (pack-skin (bindings (List SkinBinding))) (→ SkinLayout)
      (let* ((b (combined-binding bindings)) (vs (● b vertices)))
        (new SkinLayout
          (bytes (pack influence-shape vs))
          (joints (● b slots))
          (vertices (length vs)))))

    ;; The mean of posed vertices is the sum of the posed, weighted bind moments.
    ;; Accumulate them once. A rigid shell needs one matrix product per frame.
    (define (blend-pose (mesh BlendMesh) (prefix I64) (layout SkinLayout)) (→ BlendPose)
      (let* ((slots (● layout joints)) (zero (v4 0.0 0.0 0.0 0.0))
             (sum (make-array (+ 1 slots) zero)) (points (● mesh points))
             (bytes (● layout bytes)) (size (i64->f32 (array-length points))))
        (let loop ((i 0))
          (when (< i (array-length points))
            (let* ((p (array-ref points i)) (vertex (- (+ (● mesh first-vertex) i) prefix))
                   (add (lambda ((slot I64) (weight F32)) (→ Unit)
                          (when (> weight 0.0)
                            (array-set! sum
                                        slot
                                        (plus (array-ref sum slot) (times p (/ weight size))))))))
              (if (< vertex 0) (add slots 1.0)
                  (for-each (lambda (k)
                              (let ((at (+ (* vertex 32) (* k 4))))
                                (add (u32 bytes at) (bits->f32 (i64->i32 (u32 bytes (+ at 16)))))))
                            (list 0 1 2 3)))
              (loop (+ i 1)))))
        (new BlendPose (draw (● mesh draw))
             (joints (map (lambda (j) (new Pair (first j) (second (array-ref sum j))))
                          (filter (lambda (j) (> (● (array-ref sum j) w) 0.0))
                                  (iota (+ slots 1))))))))
    (define (update-blend-centers! (centers (List BlendPose)) (palette (List Mat4x4f))) (→ Unit)
      (unless (null? centers)
        (let ((poses (list->array palette)))
          (for-each
           (lambda (mesh)
             (let ((c (fold-left (lambda (total joint)
                                   (let ((j (● joint first)) (p (● joint second)))
                                     (plus total (if (= j (array-length poses)) p
                                                     (product-column (array-ref poses j) p)))))
                                 (v4 0.0 0.0 0.0 0.0) (● mesh joints))))
               (set! (● mesh draw center) (new Vec3f (x (● c x)) (y (● c y)) (z (● c z))))))
           centers))))
    (define (skin-with-layout (gpu Gpu) (source Scene) (layout SkinLayout)) (→ MovingScene)
      (let* ((joints (● layout joints))
             (total (● layout vertices)) (size (* vertex-stride (● source vertex-count))))
        (unless (and (> total 0) (<= total (● source vertex-count))) (panic "invalid skin size"))
        (let* ((ids (storage-of gpu "scene/influences" (● layout bytes)))
               (world (storage-buffer gpu "scene/world" size (list (Vertex) (CopyDst) (CopySrc))))
               (poses (storage-buffer gpu
                                      "scene/joints"
                                      (* (stride matrix-shape) joints)
                                      (list (CopyDst))))
               (module ((● gpu create-shader-module)
                        (new ShaderModuleDescriptor (label "scene/pose")
                             (code (string-append (declarations unpack-shape) unpack-shader)))))
               (kernel (compute-kernel gpu module "scene" "pose_vertices"))
               (encoder ((● gpu create-command-encoder))))
          ((● gpu destroy) (ModuleObject module))
          ((● gpu copy-buffer-to-buffer) encoder (● source vertices) 0 world 0 (i64->i32 size))
          ((● gpu submit) (list ((● gpu finish) encoder)))
          (new MovingScene (scene (Scene-vertices-set source world))
               (rest (● source vertices))
               (influences ids)
               (poses poses)
               (joints joints)
               (centers (let ((prefix (- (● source vertex-count) total)))
                          (map (lambda (mesh) (blend-pose mesh prefix layout))
                               (filter (lambda (mesh)
                                         (> (+ (● mesh first-vertex) (array-length (● mesh points)))
                                            prefix))
                                       (● source blend-meshes)))))
               (vertices total)
               (pipeline kernel)
               (group (kernel-group gpu kernel 0 "scene/pose"
                                    (list (BufferEntry 2 world 0 0)
                                          (BufferEntry 4 (● source vertices) 0 0)
                                          (BufferEntry 5 ids 0 0)
                                          (BufferEntry 6 poses 0 0))))))))

    (define (deform-scene! (gpu Gpu) (scene MovingScene) (palette (List Mat4x4f))) (→ Unit)
      (unless (= (length palette) (● scene joints)) (panic "wrong joint palette size"))
      (update-blend-centers! (● scene centers) palette)
      ((● gpu write-buffer) (● scene poses) 0 (pack matrix-shape palette))
      (let* ((encoder ((● gpu create-command-encoder))) (pass ((● gpu begin-compute-pass) encoder)))
        ((● gpu set-compute-pipeline) pass (● scene pipeline))
        ((● gpu set-compute-bind-group) pass 0 (● scene group))
        (dispatch-items gpu pass (● scene vertices) 256)
        ((● gpu end-compute-pass) pass)
        ((● gpu submit) (list ((● gpu finish) encoder)))))

    (define (release-moving-scene (gpu Gpu) (scene MovingScene)) (→ Unit)
      ((● gpu destroy) (BindGroupObject (● scene group)))
      ((● gpu destroy) (ComputePipelineObject (● scene pipeline)))
      (for-each (lambda (b) ((● gpu destroy) (BufferObject b)))
                (list (● scene influences) (● scene poses) (● scene rest)))
      (release-scene gpu (● scene scene)))

    ;; ---- Sources ----

    ;; The files the scene's buffers and images name.
    (define (file-paths (gltf Gltf)) (→ (List String))
      (source-paths
       (append (map (lambda (buffer) (● buffer source)) (● gltf buffers)) (● gltf images))))
    (define (source-paths (sources (List Source))) (→ (List String))
      (fold-right (lambda (source paths)
                    (match source
                      ((FileSource path) (Cons path paths))
                      (_ paths)))
                  (Nil)
                  sources))

    ;; A scene with something to draw, at least a unit across.
    (define (drawable (gltf Gltf)) (→ Gltf)
      (if (null? (● gltf placed))
          (unreadable "the scene has no triangles")
          (at-least-a-unit gltf)))

    (define (at-least-a-unit (gltf Gltf)) (→ Gltf)
      (let* ((bounds (gltf-bounds gltf))
             (extent (fold-left max
                                0.0
                                (map (lambda (axis)
                                       (- (list-ref (● bounds second) axis)
                                          (list-ref (● bounds first) axis)))
                                     (iota 3)))))
        (if (and (> extent 0.0) (< extent 1.0)) (gltf-scaled gltf (/ 1.0 extent)) gltf)))

    ;; Up to and with its last slash.
    (define (directory-of (url String)) (→ String)
      (let ((chars (string->array url)))
        (substring url 0 (fold-left (lambda (end index)
                                      (if (char=? (array-ref chars index) #\/) (+ index 1) end))
                                    0
                                    (iota (array-length chars))))))



    ;; A scene without materials draws with glTF's default, white and
    ;; rough.
    (define (surface-material (m Material)) (→ SurfaceMaterial)
      (let ((color (map f64->f32 (● m base-color))) (glow (map f64->f32 (● m emissive))))
        (new SurfaceMaterial
          (base-color (new Vec4f
                        (x (list-ref color 0))
                        (y (list-ref color 1))
                        (z (list-ref color 2))
                        (w (list-ref color 3))))
          (emissive (new Vec4f (x (list-ref glow 0)) (y (list-ref glow 1)) (z (list-ref glow 2))
                         (w (f64->f32 (● m alpha-cutoff)))))
          (factors (new Vec4f
                     (x (f64->f32 (● m metallic)))
                     (y (f64->f32 (● m roughness)))
                     (z (f64->f32 (● m normal-scale)))
                     (w (i64->f32 (alpha-code (● m alpha))))))
          (textures (new Vec4i
                      (x (i64->i32 (● m base-texture)))
                      (y (i64->i32 (● m metal-rough-texture)))
                      (z (i64->i32 (● m normal-texture)))
                      (w (i64->i32 (● m emissive-texture)))))
          (optics
           (new Vec4f (z (f64->f32 (● m occlusion-strength))) (w (i64->f32 (● m occlusion-texture)))
                (x (f64->f32 (● m diffuse-transmission)))
                (y (f64->f32 (● m fiber-anisotropy)))))
          (flags
           (new Vec4i
             (x (if (● m double-sided) 1 0))
             (y (if (● m water) 1 0))
             (z (i64->i32 (f64->i64 (round (* 255.0 (● m subsurface))))))
             (w (if (● m ground-layer) 1 0)))))))

    ;; ---- Geometry ----

    ;; One placed primitive's accessors as unpack.wgsl.scm reads them, and
    ;; the matrices that place its positions and its normals.
    (record Unpack
      ((first-vertex I32)
       (first-index I32)
       (material I32)
       (pad I32)
       (positions Vec4i)
       (normals Vec4i)
       (uvs Vec4i)
       (tangents Vec4i)
       (indices Vec4i)
       (matrix Mat4x4f)
       (normal-matrix Mat4x4f))
      (deriving Pod))

    (define unpack-shape (→ (Shape Unpack)) (shape))

    ;; How many vertices and indices the placed primitives have in all.
    (define (placed-counts (gltf Gltf)) (→ (Pair I64 I64))
      (fold-left (lambda (counts placed)
                   (new Pair
                     (first (+ (● counts first) (● placed primitive positions count)))
                     (second (+ (● counts second) (index-count (● placed primitive))))))
                 (new Pair (first 0) (second 0))
                 (● gltf placed)))

    (define (index-count (primitive Primitive)) (→ I64)
      (match (● primitive indices)
        ((Some indices) (* 3 (quotient (● indices count) 3)))
        ((None) (* 3 (quotient (● primitive positions count) 3)))))

    ;; Each placed primitive's Unpack, from the first vertex and index of
    ;; the ones before it.
    (define (unpacks-of (gltf Gltf)) (→ (List Unpack))
      (reverse (● (fold-left (lambda (state placed)
                               (let ((at (● state first)))
                                 (new Pair
                                   (first (new Pair
                                            (first
                                             (+ (● at first) (● placed primitive positions count)))
                                            (second
                                             (+ (● at second) (index-count (● placed primitive))))))
                                   (second (Cons (unpack-of placed (● at first) (● at second))
                                                 (● state second))))))
                             (new Pair (first (new Pair (first 0) (second 0))) (second (Nil)))
                             (● gltf placed))
                  second)))

    (define (unpack-of (placed Placed) (first-vertex I64) (first-index I64)) (→ Unpack)
      (let ((primitive (● placed primitive)))
        (new Unpack
          (first-vertex (i64->i32 first-vertex))
          (first-index (i64->i32 first-index))
          (material (i64->i32 (max 0 (● primitive material))))
          (pad 0)
          (positions (accessor (Some (● primitive positions))))
          (normals (accessor (● primitive normals)))
          (uvs (accessor (● primitive uvs)))
          (tangents (accessor (● primitive tangents)))
          (indices (accessor (● primitive indices)))
          (matrix (matrix-from (● placed matrix)))
          (normal-matrix (matrix-from (normal-matrix (● placed matrix)))))))

    (define (accessor (attribute (Option Attribute))) (→ Vec4i)
      (match attribute
        ((Some a)
         (new Vec4i
           (x (i64->i32 (● a offset)))
           (y (i64->i32 (● a stride)))
           (z (i64->i32 (● a component)))
           (w (if (● a normalized) 1 0))))
        ((None) (new Vec4i (x -1) (y 0) (z 0) (w 0)))))

    ;; The inverse transpose of the upper 3x3, up to a positive scale: its
    ;; cofactors, negated when the matrix mirrors, so normals stay outward.
    (define (normal-matrix (m (List F64))) (→ (List F64))
      (let* ((at (lambda ((r I64) (c I64))
                   (→ F64)
                   (list-ref m (+ (* 4 (remainder c 3)) (remainder r 3)))))
             (cofactor (lambda ((r I64) (c I64)) (→ F64)
                         (- (* (at (+ r 1) (+ c 1)) (at (+ r 2) (+ c 2)))
                            (* (at (+ r 1) (+ c 2)) (at (+ r 2) (+ c 1))))))
             (det (+ (* (at 0 0) (cofactor 0 0))
                     (+ (* (at 0 1) (cofactor 0 1)) (* (at 0 2) (cofactor 0 2)))))
             (sign (if (< det 0.0) -1.0 1.0)))
        (concatenate (map (lambda (c)
                            (if (= c 3)
                                (list 0.0 0.0 0.0 1.0)
                                (list (* sign (cofactor 0 c))
                                      (* sign (cofactor 1 c))
                                      (* sign (cofactor 2 c))
                                      0.0)))
                          (iota 4)))))

    ;; The scene's buffers laid end to end on the device, unpacked into the
    ;; vertex and index buffers.
    (define (unpacked (gpu Gpu) (gltf Gltf) (counts (Pair I64 I64)) (buffers (List Bytes)))
      (→ (Pair GpuBuffer GpuBuffer))
      (let* ((data (storage-buffer gpu "scene/data" (● gltf size) (list (CopyDst))))
             (unpacks (storage-of gpu "scene/unpacks" (pack unpack-shape (unpacks-of gltf))))
             (vertices
              (storage-buffer gpu
                              "scene/vertices"
                              (* vertex-stride (● counts first))
                              (list (Vertex) (CopySrc))))
             (indices (storage-buffer gpu "scene/indices" (* 4 (● counts second)) (list (Index)))))
        (for-each (lambda (laid)
                    ((● gpu write-buffer) data
                     (i64->i32 (● laid first start))
                     (padded-bytes (● laid second))))
                  (zip (● gltf buffers) buffers))
        (run-unpack gpu
                    data
                    unpacks
                    vertices
                    indices
                    (● counts first)
                    (quotient (● counts second) 3))
        ((● gpu destroy) (BufferObject data))
        ((● gpu destroy) (BufferObject unpacks))
        (new Pair (first vertices) (second indices))))

    ;; A write's size is a multiple of 4.
    (define (padded-bytes (bytes Bytes)) (→ Bytes)
      (let ((extra (remainder (- 4 (remainder (array-length bytes) 4)) 4)))
        (if (= extra 0) bytes (array-append bytes (make-array extra (i32->u8 0))))))

    (define (run-unpack (gpu Gpu) (data GpuBuffer)
                        (unpacks GpuBuffer)
                        (vertices GpuBuffer)
                        (indices GpuBuffer)
                        (vertex-count I64)
                        (triangle-count I64))
      (→ Unit)
      (let* ((module ((● gpu create-shader-module) (new ShaderModuleDescriptor
                                                     (label "scene/unpack")
                                                     (code
                                                      (string-append (declarations unpack-shape)
                                                                     unpack-shader)))))
             (encoder ((● gpu create-command-encoder)))
             (pass ((● gpu begin-compute-pass) encoder))
             (read (list (BufferEntry 0 data 0 0) (BufferEntry 1 unpacks 0 0))))
        (unpack gpu pass
                module
                "unpack_vertices"
                vertex-count
                (append read (list (BufferEntry 2 vertices 0 0))))
        (unpack gpu pass
                module
                "unpack_triangles"
                triangle-count
                (append read (list (BufferEntry 3 indices 0 0))))
        ((● gpu destroy) (ModuleObject module))
        ((● gpu end-compute-pass) pass)
        ((● gpu submit) (list ((● gpu finish) encoder)))))

    ;; One kernel of the unpack over `count` items; its pipeline and group
    ;; go at the submit.
    (define (unpack (gpu Gpu) (pass GpuComputePass)
                    (module GpuShaderModule)
                    (entry String)
                    (count I64)
                    (entries (List BindGroupEntry)))
      (→ Unit)
      (let* ((kernel (compute-kernel gpu module "scene" entry))
             (group (kernel-group gpu kernel 0 "scene/unpack" entries)))
        ((● gpu set-compute-pipeline) pass kernel)
        ((● gpu set-compute-bind-group) pass 0 group)
        (dispatch-items gpu pass count 256)
        ((● gpu destroy) (BindGroupObject group))
        ((● gpu destroy) (ComputePipelineObject kernel))))

    (define (storage-of (gpu Gpu) (label String) (bytes Bytes)) (→ GpuBuffer)
      (let ((buffer (storage-buffer gpu label (array-length bytes) (list (CopyDst)))))
        ((● gpu write-buffer) buffer 0 bytes)
        buffer))

    ;; ---- Texture maps ----
    ;; A real 2D texture per glTF image. The last entry is a white texel
    ;; bound to missing maps. The material controls which inputs it uses.
    (define (scene-maps (gpu Gpu) (images (List Bytes))) (→ (Array MapImage))
      (let* ((decoded (decode-maps gpu images (Nil))) (blit (make-compositor gpu (Rgba8Unorm)))
             (maps (map (lambda (im) (upload-map gpu blit im)) decoded))
             (white (make-plane gpu
                                "material/white"
                                1
                                1
                                (Rgba8Unorm)
                                (list (TextureBinding) (TextureCopyDst)))))
        (release-compositor gpu blit)
        ((● gpu write-texture) (whole-texture (● white texture)) 4 1 1 (make-array 4 (i32->u8 255)))
        (list->array
         (append maps (list (new MapImage (texture (● white texture)) (view (● white view))))))))
    (define (decode-maps (gpu Gpu) (bytes (List Bytes)) (ready (List Image))) (→ (List Image))
      (match bytes ((Nil) (reverse ready))
             ((Cons data more)
              (match ((● gpu decode-image) data)
                ((Some im) (decode-maps gpu more (Cons im ready)))
                ((None)
                 (for-each (lambda (im) ((● gpu destroy) (TextureObject (● im texture)))) ready)
                 (unreadable "unsupported material image"))))))
    (define (upload-map (gpu Gpu) (blit Compositor) (im Image)) (→ MapImage)
      (let* ((w (● im width)) (h (● im height)) (mips (levels (max w h)))
             (texture ((● gpu create-texture) (new TextureDescriptor (label "material/image")
                                                   (width w)
                                                   (height h)
                                                   (layers 1)
                                                   (mips mips)
                                                   (format (Rgba8Unorm))
                                                   (usage
                                                    (list (TextureBinding) (RenderAttachment))))))
             (encoder ((● gpu create-command-encoder))))
        (let loop ((level 0) (source (view-of gpu (● im texture) 1)))
          (if (= level mips) ((● gpu destroy) (ViewObject source))
              (let ((target (level-view gpu texture level)))
                (composite! gpu blit encoder source target)
                ((● gpu destroy) (ViewObject source))
                (loop (+ level 1) target))))
        ((● gpu submit) (list ((● gpu finish) encoder)))
        ((● gpu destroy) (TextureObject (● im texture)))
        (new MapImage (texture texture) (view (view-of gpu texture mips)))))
    ;; Levels down to 1 by 1.
    (define (levels (size I32)) (→ I32) (if (<= size 1) 1 (+ 1 (levels (quotient size 2)))))

    (define (level-view (gpu Gpu) (texture GpuTexture) (level I32)) (→ GpuTextureView)
      ((● gpu create-view) texture (new TextureViewDescriptor (dimension (View2d))
                                        (base-mip level) (mips 1) (base-layer 0) (layers 1))))
    (define (repeating-sampler (gpu Gpu)) (→ GpuSampler)
      ((● gpu create-sampler) (new SamplerDescriptor
                                (label "scene/repeat")
                                (mag-filter (Linear))
                                (min-filter (Linear))
                                (mipmap-filter (Linear))
                                (address (Repeat)))))

    ))
