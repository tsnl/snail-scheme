;; A glTF scene on the device, loaded once from its files: every triangle in
;; the world in one vertex and one index buffer, unpacked from the scene's
;; buffers by a compute pass (unpack.wgsl.scm); the materials in one
;; storage buffer; and every image in one layer of one texture array with
;; its mips (layers.wgsl.scm), since WebGPU binds no unbounded table of
;; textures. A layer is `layer-size` square whatever the image's size, and
;; a material names its textures by layer. Rasterizing and tracing read
;; the same buffers, so what is drawn is what rays hit.
;;
;;   (match (attempt-reading
;;           (lambda () (load-scene read "models/Sponza/glTF/Sponza.gltf" 1024)))
;;     ((Ok scene) ...)
;;     ((Err why) ...))
(define-library (snail shell graphics trace scene)
  (export
   Scene
   SurfaceRun
   SurfaceMaterial
   EmitterTable
   Scene-emitters-set
   scene-emitters
   make-emitter-table
   release-emitter-table
   load-scene
   upload-scene upload-lit-scene upload-with-images
   SceneImages
   scene-materials
   ObjectPose
   MovingScene
   moving-scene
   skin-scene
   SkinLayout pack-skin skin-with-layout
   pose-matrix
   deform-scene!
   pose-scene!
   release-moving-scene
   release-scene
   vertex-stride
   scene-triangles)
  (import
   (snail core base)
   (snail shell gpu)
   (snail shell graphics pod)
   (only (snail shell graphics animation)
         Influence
         SkinBinding
         rigid-binding
         shift-influence
         v4
         matrix-from)
   (snail shell graphics kernel)
   (snail shell graphics gltf)
   (only (snail shell graphics bvh) Triangles TriangleSpan)
   (snail shell graphics trace lights)
   (only (snail shell graphics raster) Plane make-plane release-plane)
   (snail shell graphics trace shaders))
  (begin

    ;; ---- The scene ----

    ;; The vertices, 64 bytes each (unpack.wgsl.scm's Vertex), three
    ;; indices a triangle, the materials, the texture array with a view of
    ;; all its levels and the sampler that repeats it, the box around
    ;; every vertex, low corner then high, and whether any material is
    ;; blended, which the tracer draws as a layer of its own. Then each
    ;; placed primitive's vertices and triangles, in order, and the spans
    ;; of triangles that move, an object each, which a moving scene sets.
    ;; Each scene holds one reference to its texture array. Neighbouring scenes
    ;; can share an ordered image table while either remains drawable.
    (record SceneImages
      ((texture GpuTexture)
       (size I32)
       (count I64)
       (users I64)))
    (record Scene
      ((lights LightGrid)
       (emitters EmitterTable)
       (vertices GpuBuffer)
       (indices GpuBuffer)
       (materials GpuBuffer)
       (images SceneImages)
       (layers-view GpuTextureView)
       (sampler GpuSampler)
       (vertex-count I64)
       (triangle-count I64)
       (low (List F64))
       (high (List F64))
       (blended Bool)
       (parts (List (Pair I64 I64)))
       (moving (List TriangleSpan))
       (runs (List SurfaceRun))))

    ;; A run of triangles whose materials share an alpha mode (0 opaque, 1
    ;; masked, 2 blended), which the tracer draws with one pipeline.
    (record SurfaceRun
      ((first I64)
       (count I64)
       (alpha I64)))

    ;; The scene's triangles as runs, in order: each placed primitive's,
    ;; merged with the one before where both have the same alpha mode.
    (define (surface-runs (gltf Gltf)) (→ (List SurfaceRun))
      (let ((materials (list->array (scene-materials gltf))))
        (reverse
         (fold-left (lambda (runs p)
                      (let ((n (quotient (index-count (● p primitive)) 3))
                            (alpha
                             (● (array-ref materials (max 0 (● p primitive material))) alpha)))
                        (match runs
                          ((Cons r rest)
                           (if (= (● r alpha) alpha)
                               (Cons (SurfaceRun-count-set r (+ (● r count) n)) rest)
                               (Cons (new SurfaceRun (first (+ (● r first) (● r count))) (count n)
                                          (alpha alpha))
                                     runs)))
                          ((Nil) (list (new SurfaceRun (first 0) (count n) (alpha alpha)))))))
                    (ann (Nil) (List SurfaceRun))
                    (● gltf placed)))))

    (define vertex-stride (→ I64) 64)

    ;; The scene's triangles as a BVH reads them: a vertex's position is
    ;; its first three words, and the moving spans are the scene's.
    (define (scene-triangles (scene Scene)) (→ Triangles)
      (new Triangles
        (positions (● scene vertices))
        (stride (i64->i32 (quotient vertex-stride 4)))
        (offset 0)
        (indices (● scene indices))
        (count (● scene triangle-count))
        (moving (● scene moving))))

    ;; A material as the shaders read it: its base color; its emission,
    ;; with the alpha cutoff in w; its metalness, roughness, normal scale
    ;; and alpha mode (0 opaque, 1 mask, 2 blend); and the layers of its
    ;; base color, metal-roughness, normal and emissive textures, -1 for
    ;; none, then whether it is double-sided.
    (record SurfaceMaterial
      ((base-color Vec4f)
       (emissive Vec4f)
       (factors Vec4f)
       (textures Vec4i)
       (flags Vec4i))
      (deriving Pod))

    (define material-shape (→ (Shape SurfaceMaterial)) (shape))

    ;; The scene whose .gltf or .glb is at `path`, its files read by `read`,
    ;; which answers the bytes of each path it is given, in order; the
    ;; scene's URIs are relative to its directory. The files its buffers
    ;; and images name are asked for together, so a page fetches them at
    ;; once. A scene that cannot be read refuses (`reading`, of (snail
    ;; shell graphics gltf)) and leaves nothing on the device: `read` may
    ;; refuse a path, the scene may be one `read-gltf` refuses, a file may
    ;; be shorter than the scene says, or an image one the host does not
    ;; decode. A scene less than a unit
    ;; across is made one unit across, since a camera clips at a tenth of
    ;; a unit and rays leave surfaces by a fixed offset.
    (define (load-scene (gpu Gpu) (read (Fn (List String) → (List Bytes)))
                        (path String)
                        (layer-size I32))
      (→ Scene)
      (upload-scene gpu
                    read
                    (drawable (read-gltf (list-ref (read (list path)) 0) (directory-of path)))
                    layer-size))

    (define (upload-scene (gpu Gpu)
                          (read (Fn (List String) → (List Bytes)))
                          (gltf Gltf)
                          (layer-size I32))
      (→ Scene)
      (upload-lit-scene gpu read gltf layer-size (Nil) 0))
    (define (upload-lit-scene (gpu Gpu) (read (Fn (List String) → (List Bytes)))
                              (gltf Gltf) (layer-size I32) (lights (List Punctual)) (capacity I64))
      (→ Scene)
      (let* ((paths (file-paths gltf))
             (files (zip paths (read paths)))
             (buffers (map (lambda (buffer) (buffer-bytes buffer files)) (● gltf buffers)))
             (layers (load-layers gpu (map (lambda (image) (source-bytes image files buffers))
                                           (● gltf images))
                                  layer-size)))
        (on-device gpu gltf buffers
                   (new SceneImages
                     (texture layers)
                     (size layer-size)
                     (count (length (● gltf images)))
                     (users 0))
                   (light-grid gpu lights capacity))))

    ;; The caller supplies the same ordered glTF image table. Only vertex
    ;; buffers are read; a district change never decodes the same images again.
    (define (upload-with-images (gpu Gpu) (read (Fn (List String) → (List Bytes)))
                                (gltf Gltf)
                                (images SceneImages)
                                (lights (List Punctual))
                                (capacity I64))
      (→ Scene)
      (unless (= (length (● gltf images)) (● images count)) (panic "scene image table changed"))
      (let* ((paths (source-paths (map (lambda (b) (● b source)) (● gltf buffers))))
             (files (zip paths (read paths))))
        (on-device gpu gltf (map (lambda (b) (buffer-bytes b files)) (● gltf buffers))
                   images (light-grid gpu lights capacity))))

    ;; Nothing refuses once the layers are loaded, so a scene refused
    ;; leaves nothing on the device.
    (define (on-device (gpu Gpu)
                       (gltf Gltf)
                       (buffers (List Bytes))
                       (images SceneImages)
                       (lights LightGrid))
      (→ Scene)
      (let* ((counts (placed-counts gltf))
             (geometry (unpacked gpu gltf counts buffers))
             (materials (storage-of gpu "scene/materials"
                                    (pack material-shape
                                          (map surface-material (scene-materials gltf)))))
             (bounds (gltf-bounds gltf)))
        (set! (● images users) (+ (● images users) 1))
        (new Scene
          (lights lights)
          (emitters (make-emitter-table gpu (scene-emitters gltf)
                                        (● geometry first) (● geometry second) materials))
          (vertices (● geometry first))
          (indices (● geometry second))
          (materials materials)
          (images images)
          (layers-view ((● gpu create-view) (● images texture)
                        (new TextureViewDescriptor
                          (dimension (View2dArray))
                          (base-mip 0)
                          (mips (levels (● images size)))
                          (base-layer 0)
                          (layers 0))))
          (sampler (repeating-sampler gpu))
          (vertex-count (● counts first))
          (triangle-count (quotient (● counts second) 3))
          (low (● bounds first))
          (high (● bounds second))
          (blended (any? (lambda (m) (= (● m alpha) 2)) (scene-materials gltf)))
          (parts (map (lambda (p)
                        (new Pair
                          (first (● p primitive positions count))
                          (second (quotient (index-count (● p primitive)) 3))))
                      (● gltf placed)))
          (moving (Nil))
          (runs (surface-runs gltf)))))

    (define (release-scene (gpu Gpu) (scene Scene)) (→ Unit)
      (release-plane gpu (● scene lights plane))
      (release-emitter-table gpu (● scene emitters))
      (for-each (lambda (buffer) ((● gpu destroy) (BufferObject buffer)))
                (list (● scene vertices) (● scene indices) (● scene materials)))
      ((● gpu destroy) (ViewObject (● scene layers-view)))
      (let ((images (● scene images)))
        (set! (● images users) (- (● images users) 1))
        (when (= (● images users) 0) ((● gpu destroy) (TextureObject (● images texture)))))
      ((● gpu destroy) (SamplerObject (● scene sampler))))

    ;; ---- Sampling mesh lights ----

    ;; One entry per opaque triangle with constant emission, in triangle ID
    ;; order. Other emissive materials are still evaluated at ordinary hits.
    (record EmitterTable
      ((triangles Plane)
       (distribution Plane)
       (count I64)))

    (define (scene-emitters (gltf Gltf)) (→ (List I32))
      (let ((materials (list->array (scene-materials gltf))))
        (let loop ((placed (● gltf placed)) (first 0) (ids (ann (Nil) (List I32))))
          (match placed
            ((Nil) (reverse ids))
            ((Cons p tail)
             (let* ((prim (● p primitive)) (n (quotient (index-count prim) 3))
                    (m (array-ref materials (max 0 (● prim material)))))
               (loop tail (+ first n)
                     (if (and (= (● m alpha) 0) (< (● m emissive-texture) 0)
                              (any? (lambda (v) (> v 0.0)) (● m emissive)))
                         (fold-left (lambda (out i) (Cons (i64->i32 (+ first i)) out)) ids (iota n))
                         ids))))))))

    (define triangle-id-shape (→ (Shape I32)) (shape))

    ;; Forward sampling and the inverse lookup at a BSDF hit must name
    ;; exactly the same set of triangles.
    (define (emitter-count (ids (List I32))) (→ I64)
      (let loop ((rest ids) (previous (ann -1 I32)) (n 0))
        (match rest
          ((Nil) n)
          ((Cons id tail)
           (unless (> id previous)
             (panic "emitter triangle IDs must be nonnegative and strictly increasing"))
           (loop tail id (+ n 1))))))

    ;; Each row stores emission.rgb and inclusive sums of rest area × luminance.
    ;; The extra column holds cumulative row sums. The GPU reads the same
    ;; unpacked triangles as the tracer. No vertex readback is needed.
    (define (make-emitter-table (gpu Gpu) (ids (List I32)) (vertices GpuBuffer)
                                (indices GpuBuffer) (materials GpuBuffer)) (→ EmitterTable)
                                (let* ((n (emitter-count ids))
                                       (width (max 1 (f64->i64 (ceiling (sqrt (i64->f64 n))))))
                                       (height (max 1 (quotient (+ n (- width 1)) width)))
                                       (w (i64->i32 width)) (h (i64->i32 height))
                                       (triangles (make-plane gpu "emitters/triangles" w h (R32Uint)
                                                              (list (TextureCopySrc)
                                                                    (TextureBinding)
                                                                    (TextureCopyDst))))
                                       (table (make-plane gpu
                                                          "emitters/distribution"
                                                          (+ w 1)
                                                          h
                                                          (Rgba32Float)
                                                          (list (TextureCopySrc) (TextureBinding)
                                                                (StorageBinding)))))
                                  ((● gpu write-texture)
                                   (whole-texture (● triangles texture))
                                   (* 4 w)
                                   w
                                   h
                                   (pack triangle-id-shape
                                         (append ids
                                                 (map (lambda (_) -1)
                                                      (iota (- (* width height) n))))))
                                  (when (> n 0)
                                    (weigh-emitters gpu
                                                    triangles
                                                    table
                                                    vertices
                                                    indices
                                                    materials
                                                    height))
                                  (new EmitterTable
                                    (triangles triangles)
                                    (distribution table)
                                    (count n))))

    (define (weigh-emitters (gpu Gpu) (ids Plane) (table Plane) (vertices GpuBuffer)
                            (indices GpuBuffer) (materials GpuBuffer) (rows I64)) (→ Unit)
                            (let* ((module ((● gpu create-shader-module) (new ShaderModuleDescriptor
                                                                           (label "emitters/weigh")
                                                                           (code
                                                                            (string-append
                                                                             (declarations
                                                                              material-shape)
                                                                             scene-shader
                                                                             emitter-build-shader)))))
                                   (sums (storage-buffer gpu "emitters/row-sums" (* 4 rows) (Nil)))
                                   (encoder ((● gpu create-command-encoder)))
                                   (pass ((● gpu begin-compute-pass) encoder))
                                   (shared (list (TextureEntry 0 (● ids view))
                                                 (TextureEntry 1 (● table view))
                                                 (BufferEntry 2 sums 0 0)))
                                   (weigh (compute-kernel gpu module "emitters" "weigh_rows"))
                                   (marginal
                                    (compute-kernel gpu module "emitters" "weigh_marginal"))
                                   (inputs (kernel-group gpu weigh 0 "emitters/table" shared))
                                   (mesh (kernel-group gpu weigh 1 "emitters/mesh"
                                                       (list (BufferEntry 0 vertices 0 0)
                                                             (BufferEntry 1 indices 0 0)
                                                             (BufferEntry 2 materials 0 0))))
                                   (output
                                    (kernel-group gpu marginal 0 "emitters/marginal" shared)))
                              ((● gpu set-compute-pipeline) pass weigh)
                              ((● gpu set-compute-bind-group) pass 0 inputs)
                              ((● gpu set-compute-bind-group) pass 1 mesh)
                              (dispatch-items gpu pass rows 64)
                              ((● gpu set-compute-pipeline) pass marginal)
                              ((● gpu set-compute-bind-group) pass 0 output)
                              ((● gpu dispatch-workgroups) pass 1 1 1)
                              ((● gpu end-compute-pass) pass)
                              ((● gpu submit) (list ((● gpu finish) encoder)))
                              (for-each (lambda (object) ((● gpu destroy) object))
                                        (list (BufferObject sums)
                                              (ModuleObject module)
                                              (ComputePipelineObject weigh)
                                              (ComputePipelineObject marginal)
                                              (BindGroupObject inputs)
                                              (BindGroupObject mesh) (BindGroupObject output)))))

    (define (release-emitter-table (gpu Gpu) (table EmitterTable)) (→ Unit)
      (release-plane gpu (● table triangles))
      (release-plane gpu (● table distribution)))

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
    ;; influences whenever only the static prefix of the world changes. Each
    ;; binding's vertex count is kept: a binding is an object, and each
    ;; object's triangles get a tree of their own (moving-spans).
    (record SkinLayout
      ((bytes Bytes)
       (joints I64)
       (vertices I64)
       (objects (List I64))))
    (define (pack-skin (bindings (List SkinBinding))) (→ SkinLayout)
      (let* ((b (combined-binding bindings)) (vs (● b vertices)))
        (new SkinLayout
          (bytes (pack influence-shape vs))
          (joints (● b slots))
          (vertices (length vs))
          (objects (map (lambda (binding) (length (● binding vertices))) bindings)))))

    ;; The moving triangles' spans, an object each. The objects' vertices
    ;; are the scene's last, in binding order, and begin where a placed
    ;; primitive does; each object's span is the triangles of the
    ;; primitives its vertices cover. Objects that share a primitive share
    ;; a span.
    (define (moving-spans (scene Scene) (objects (List I64))) (→ (List TriangleSpan))
      (let ((start (- (● scene vertex-count) (fold-left + 0 objects))))
        (let walk ((parts (● scene parts)) (v 0) (t 0))
          (if (= v start) (object-spans parts objects 0 t 0)
              (match parts
                ((Cons p rest)
                 (when (> (+ v (● p first)) start)
                   (panic "moving vertices must begin where a placed primitive does"))
                 (walk rest (+ v (● p first)) (+ t (● p second))))
                ((Nil) (panic "moving vertices must begin where a placed primitive does")))))))

    ;; `left` is how many of the current objects' vertices the primitives
    ;; taken so far have not covered, below 0 where a primitive runs into
    ;; the next object; `count` is the triangles taken since the last span.
    (define (object-spans (parts (List (Pair I64 I64))) (objects (List I64)) (left I64)
                          (first I64) (count I64))
      (→ (List TriangleSpan))
      (match objects
        ((Cons n more)
         (if (or (< left 0) (and (= left 0) (= count 0)))
             (object-spans parts more (+ left n) first count)
             (covered parts objects left first count)))
        ((Nil) (covered parts objects left first count))))

    ;; A span where the objects' vertices end, or the next primitive taken.
    (define (covered (parts (List (Pair I64 I64))) (objects (List I64)) (left I64)
                     (first I64) (count I64))
      (→ (List TriangleSpan))
      (cond ((and (= left 0) (> count 0))
             (Cons (new TriangleSpan (first first) (count count))
                   (object-spans parts objects 0 (+ first count) 0)))
            ((> left 0)
             (match parts
               ((Cons p rest)
                (object-spans rest objects (- left (● p first)) first (+ count (● p second))))
               ((Nil) (panic "moving vertices run past the placed primitives"))))
            ((< left 0) (panic "a placed primitive runs past the moving vertices"))
            (else (Nil))))
    (define (skin-with-layout (gpu Gpu) (source Scene) (layout SkinLayout)) (→ MovingScene)
      (let* ((joints (● layout joints))
             (total (● layout vertices)) (size (* vertex-stride (● source vertex-count))))
        (unless (and (> total 0) (<= total (● source vertex-count))) (panic "invalid skin size"))
        (let* ((ids (storage-of gpu "scene/influences" (● layout bytes)))
               (world (storage-buffer gpu "scene/world" size (list (CopyDst) (CopySrc))))
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
          (new MovingScene (scene (Scene-moving-set (Scene-vertices-set source world)
                                                    (moving-spans source (● layout objects))))
               (rest (● source vertices))
               (influences ids)
               (poses poses)
               (joints joints)
               (vertices total)
               (pipeline kernel)
               (group (kernel-group gpu kernel 0 "scene/pose"
                                    (list (BufferEntry 2 world 0 0)
                                          (BufferEntry 4 (● source vertices) 0 0)
                                          (BufferEntry 5 ids 0 0)
                                          (BufferEntry 6 poses 0 0))))))))

    ;; Run once per displayed pose. The shader saves the preceding position
    ;; for reprojection, including on a second draw of the same tick.
    (define (pose-scene! (gpu Gpu) (scene MovingScene) (poses (List ObjectPose))) (→ Unit)
      (deform-scene! gpu scene (map pose-matrix poses)))

    (define (deform-scene! (gpu Gpu) (scene MovingScene) (palette (List Mat4x4f))) (→ Unit)
      (unless (= (length palette) (● scene joints)) (panic "wrong joint palette size"))
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
                     (w (i64->f32 (● m alpha)))))
          (textures (new Vec4i
                      (x (i64->i32 (● m base-texture)))
                      (y (i64->i32 (● m metal-rough-texture)))
                      (z (i64->i32 (● m normal-texture)))
                      (w (i64->i32 (● m emissive-texture)))))
          (flags
           (new Vec4i (x (if (● m double-sided) 1 0)) (y (if (● m water) 1 0)) (z 0) (w 0))))))

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
                              (list (CopySrc))))
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

    ;; ---- Textures ----

    ;; A layer for each image, at least one, each image drawn into its
    ;; first level and each next level drawn from the one before. An image
    ;; the host does not decode refuses the scene, and the layers go.
    (define (load-layers (gpu Gpu) (images (List Bytes)) (size I32))
      (→ GpuTexture)
      (let* ((layers ((● gpu create-texture) (new TextureDescriptor
                                               (label "scene/layers")
                                               (width size)
                                               (height size)
                                               (layers (i64->i32 (max 1 (length images))))
                                               (mips (levels size))
                                               (format (Rgba8Unorm))
                                               (usage (list (TextureBinding) (RenderAttachment))))))
             (pipeline (layer-pipeline gpu))
             (sampler ((● gpu create-sampler) (new SamplerDescriptor
                                                (label "scene/layers")
                                                (mag-filter (Linear))
                                                (min-filter (Linear))
                                                (mipmap-filter (Nearest))
                                                (address (ClampToEdge))))))
        (for-each (lambda (index)
                    (match ((● gpu decode-image) (list-ref images index))
                      ((Some image)
                       (fill-layer gpu layers
                                   pipeline
                                   sampler
                                   (view-of gpu (● image texture) 1)
                                   (i64->i32 index)
                                   size)
                       ((● gpu destroy) (TextureObject (● image texture))))
                      ((None)
                       (for-each (lambda (object) ((● gpu destroy) object))
                                 (list (TextureObject layers)
                                       (PipelineObject pipeline)
                                       (SamplerObject sampler)))
                       (unreadable
                        (string-append "image "
                                       (show index)
                                       " of the scene is not one read here")))))
                  (iota (length images)))
        ((● gpu destroy) (PipelineObject pipeline))
        ((● gpu destroy) (SamplerObject sampler))
        layers))

    ;; Levels down to 1 by 1.
    (define (levels (size I32)) (→ I32) (if (<= size 1) 1 (+ 1 (levels (quotient size 2)))))

    ;; Each level of layer `layer` drawn from `source`, then from the level
    ;; before.
    (define (fill-layer (gpu Gpu) (layers GpuTexture)
                        (pipeline GpuRenderPipeline)
                        (sampler GpuSampler)
                        (source GpuTextureView)
                        (layer I32)
                        (size I32))
      (→ Unit)
      (let ((encoder ((● gpu create-command-encoder))))
        (fold-left (lambda (source level)
                     (let ((target (level-view gpu layers layer (i64->i32 level))))
                       (draw-level gpu encoder pipeline sampler source target)
                       ((● gpu destroy) (ViewObject source))
                       target))
                   source
                   (iota (i32->i64 (levels size))))
        ((● gpu submit) (list ((● gpu finish) encoder)))))

    (define (level-view (gpu Gpu) (layers GpuTexture) (layer I32) (level I32))
      (→ GpuTextureView)
      ((● gpu create-view) layers
       (new TextureViewDescriptor
         (dimension (View2d))
         (base-mip level)
         (mips 1)
         (base-layer layer)
         (layers 1))))

    (define (draw-level (gpu Gpu) (encoder GpuCommandEncoder)
                        (pipeline GpuRenderPipeline)
                        (sampler GpuSampler)
                        (source GpuTextureView)
                        (target GpuTextureView))
      (→ Unit)
      (let ((group ((● gpu create-bind-group) (new BindGroupDescriptor
                                                (label "scene/layer")
                                                (pipeline (RenderPipeline pipeline))
                                                (group 0)
                                                (entries
                                                 (list (TextureEntry 0 source)
                                                       (SamplerEntry 1 sampler))))))
            (pass ((● gpu begin-render-pass) encoder
                   (new RenderPassDescriptor
                     (colors (list (Some (new ColorAttachment
                                           (view target)
                                           (load (Keep))
                                           (store #t)))))
                     (depth (None))))))
        ((● gpu set-pipeline) pass pipeline)
        ((● gpu set-bind-group) pass 0 group)
        ((● gpu draw) pass 3 1 0 0)
        ((● gpu end-pass) pass)
        ((● gpu destroy) (BindGroupObject group))))

    (define (layer-pipeline (gpu Gpu)) (→ GpuRenderPipeline)
      ((● gpu create-render-pipeline)
       (new RenderPipelineDescriptor
         (label "scene/layer")
         (module ((● gpu create-shader-module)
                  (new ShaderModuleDescriptor
                    (label "scene/layers")
                    (code layers-shader))))
         (vertex-entry "layer_vertex")
         (buffers (Nil))
         (fragment (Some (new FragmentState
                           (entry "layer_fragment")
                           (targets
                            (list (Some (new ColorTarget
                                          (format (Rgba8Unorm))
                                          (blend (None)))))))))
         (topology (TriangleList))
         (cull (CullNone))
         (depth (None)))))

    (define (repeating-sampler (gpu Gpu)) (→ GpuSampler)
      ((● gpu create-sampler) (new SamplerDescriptor
                                (label "scene/repeat")
                                (mag-filter (Linear))
                                (min-filter (Linear))
                                (mipmap-filter (Linear))
                                (address (Repeat)))))

    ))
