;; A glTF scene on the device, loaded once from its URL: every triangle in
;; the world in one vertex and one index buffer, unpacked from the scene's
;; buffers by a compute pass (unpack.wgsl.scm); the materials in one
;; storage buffer; and every image in one layer of one texture array with
;; its mips (layers.wgsl.scm), since WebGPU binds no unbounded table of
;; textures. A layer is `layer-size` square whatever the image's size, and
;; a material names its textures by layer. Rasterizing and tracing read
;; the same buffers, so what is drawn is what rays hit.
;;
;;   (let ((scene (load-scene "models/Sponza/glTF/Sponza.gltf" 1024))) ...)
(define-library (snail shell graphics trace scene)
  (export
   Scene
   SurfaceMaterial
   load-scene
   vertex-stride)
  (import
   (snail core base)
   (snail shell utf8)
   (only (snail shell task) tasks)
   (snail shell fetch)
   (snail shell gpu)
   (snail shell graphics pod)
   (snail shell graphics gltf)
   (snail shell graphics trace shaders))
  (begin

    ;; ---- The scene ----

    ;; The vertices, 64 bytes each (unpack.wgsl.scm's Vertex), three
    ;; indices a triangle, the materials, the texture array with a view of
    ;; all its levels and the sampler that repeats it, and the box around
    ;; every vertex, low corner then high.
    (record Scene
      ((vertices GpuBuffer)
       (indices GpuBuffer)
       (materials GpuBuffer)
       (layers GpuTexture)
       (layers-view GpuTextureView)
       (sampler GpuSampler)
       (vertex-count I64)
       (triangle-count I64)
       (low (List F64))
       (high (List F64))))

    (define vertex-stride (→ I64) 64)

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

    (define (load-scene (url String) (layer-size I32)) (→ Scene) (! fetch gpu tasks)
      (let ((gltf (match (read-gltf (fetched-text url) (directory-of url))
                    ((Ok gltf) gltf)
                    ((Err reason) (panic (string-append "scene: " url ": " reason))))))
        (let* ((counts (placed-counts gltf))
               (geometry (unpacked gltf counts))
               (bounds (gltf-bounds gltf))
               (layers (load-layers (● gltf images) layer-size)))
          (new Scene
            (vertices (● geometry first))
            (indices (● geometry second))
            (materials (storage-of "scene/materials"
                                   (pack material-shape
                                         (map surface-material (with-default (● gltf materials))))))
            (layers layers)
            (layers-view (create-view layers
                                      (new TextureViewDescriptor
                                        (dimension (View2dArray))
                                        (base-mip 0)
                                        (mips (levels layer-size))
                                        (base-layer 0)
                                        (layers 0))))
            (sampler (repeating-sampler))
            (vertex-count (● counts first))
            (triangle-count (quotient (● counts second) 3))
            (low (● bounds first))
            (high (● bounds second))))))

    (define (directory-of (url String)) (→ String)
      (match (string-index-right url #\/)
        ((Some at) (substring url 0 (+ at 1)))
        ((None) "")))

    (define (fetched (url String)) (→ Bytes) (! fetch tasks)
      (match (fetch-bytes url)
        ((Ok bytes) bytes)
        ((Err reason) (panic (string-append "scene: " reason)))))

    (define (fetched-text (url String)) (→ String) (! fetch tasks)
      (match (utf8->string (fetched url))
        ((Ok text) text)
        ((Err _) (panic (string-append "scene: " url " is not UTF-8")))))

    ;; A scene without materials draws with glTF's default, white and
    ;; rough.
    (define (with-default (materials (List Material))) (→ (List Material))
      (if (null? materials)
          (list (new Material
                  (base-color (list 1.0 1.0 1.0 1.0))
                  (base-texture -1)
                  (metallic 0.0)
                  (roughness 1.0)
                  (metal-rough-texture -1)
                  (normal-texture -1)
                  (normal-scale 1.0)
                  (emissive (list 0.0 0.0 0.0))
                  (emissive-texture -1)
                  (alpha 0)
                  (alpha-cutoff 0.5)
                  (double-sided #f)))
          materials))

    (define (surface-material (m Material)) (→ SurfaceMaterial)
      (let ((color (map f64->f32 (● m base-color))) (glow (map f64->f32 (● m emissive))))
        (new SurfaceMaterial
          (base-color (new Vec4f (x (list-ref color 0)) (y (list-ref color 1)) (z (list-ref color 2)) (w (list-ref color 3))))
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
          (flags (new Vec4i (x (if (● m double-sided) 1 0)) (y 0) (z 0) (w 0))))))

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
                                            (first (+ (● at first) (● placed primitive positions count)))
                                            (second (+ (● at second) (index-count (● placed primitive))))))
                                   (second (Cons (unpack-of placed (● at first) (● at second)) (● state second))))))
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
          (matrix (matrix-of (● placed matrix)))
          (normal-matrix (matrix-of (normal-matrix (● placed matrix)))))))

    (define (accessor (attribute (Option Attribute))) (→ Vec4i)
      (match attribute
        ((Some a)
         (new Vec4i
           (x (i64->i32 (● a offset)))
           (y (i64->i32 (● a stride)))
           (z (i64->i32 (● a component)))
           (w (if (● a normalized) 1 0))))
        ((None) (new Vec4i (x -1) (y 0) (z 0) (w 0)))))

    (define (matrix-of (m (List F64))) (→ Mat4x4f)
      (let ((column (lambda ((c I64)) (→ Vec4f)
                      (new Vec4f
                        (x (f64->f32 (list-ref m (* 4 c))))
                        (y (f64->f32 (list-ref m (+ (* 4 c) 1))))
                        (z (f64->f32 (list-ref m (+ (* 4 c) 2))))
                        (w (f64->f32 (list-ref m (+ (* 4 c) 3))))))))
        (new Mat4x4f (x (column 0)) (y (column 1)) (z (column 2)) (w (column 3)))))

    ;; The inverse transpose of the upper 3x3, up to a positive scale: its
    ;; cofactors, negated when the matrix mirrors, so normals stay outward.
    (define (normal-matrix (m (List F64))) (→ (List F64))
      (let* ((at (lambda ((r I64) (c I64)) (→ F64) (list-ref m (+ (* 4 (remainder c 3)) (remainder r 3)))))
             (cofactor (lambda ((r I64) (c I64)) (→ F64)
                         (- (* (at (+ r 1) (+ c 1)) (at (+ r 2) (+ c 2)))
                            (* (at (+ r 1) (+ c 2)) (at (+ r 2) (+ c 1))))))
             (det (+ (* (at 0 0) (cofactor 0 0)) (* (at 0 1) (cofactor 0 1)) (* (at 0 2) (cofactor 0 2))))
             (sign (if (< det 0.0) -1.0 1.0)))
        (concatenate (map (lambda (c)
                            (if (= c 3)
                                (list 0.0 0.0 0.0 1.0)
                                (list (* sign (cofactor 0 c)) (* sign (cofactor 1 c)) (* sign (cofactor 2 c)) 0.0)))
                          (iota 4)))))

    ;; The scene's buffers laid end to end on the device, unpacked into the
    ;; vertex and index buffers.
    (define (unpacked (gltf Gltf) (counts (Pair I64 I64))) (→ (Pair GpuBuffer GpuBuffer)) (! fetch gpu tasks)
      (let* ((data (storage-sized "scene/data" (max 4 (● gltf size)) (list (Storage) (CopyDst))))
             (unpacks (storage-of "scene/unpacks" (pack unpack-shape (unpacks-of gltf))))
             (vertices (storage-sized "scene/vertices" (max 64 (* vertex-stride (● counts first))) (list (Storage))))
             (indices (storage-sized "scene/indices" (max 12 (* 4 (● counts second))) (list (Storage) (Index)))))
        (write-buffers data (● gltf buffers))
        (run-unpack data unpacks vertices indices (● counts first) (quotient (● counts second) 3))
        (destroy (BufferObject data))
        (destroy (BufferObject unpacks))
        (new Pair (first vertices) (second indices))))

    ;; Each buffer at its start, a multiple of 4, padded to one.
    (define (write-buffers (data GpuBuffer) (urls (List String))) (→ Unit) (! fetch gpu tasks)
      (fold-left (lambda (start url)
                   (let* ((bytes (fetched url)) (padded (padded-bytes bytes)))
                     (write-buffer data (i64->i32 start) padded)
                     (+ start (array-length padded))))
                 0
                 urls)
      (unit))

    (define (padded-bytes (bytes Bytes)) (→ Bytes)
      (let ((extra (remainder (- 4 (remainder (array-length bytes) 4)) 4)))
        (if (= extra 0) bytes (array-append bytes (make-array extra (i32->u8 0))))))

    (define (run-unpack (data GpuBuffer)
                        (unpacks GpuBuffer)
                        (vertices GpuBuffer)
                        (indices GpuBuffer)
                        (vertex-count I64)
                        (triangle-count I64))
      (→ Unit)
      (! gpu)
      (let* ((module (create-shader-module (new ShaderModuleDescriptor
                                             (label "scene/unpack")
                                             (code (string-append (declarations unpack-shape) unpack-shader)))))
             (encoder (create-command-encoder))
             (pass (begin-compute-pass encoder)))
        (for-each (lambda (step)
                    (let* ((pipeline (create-compute-pipeline
                                      (new ComputePipelineDescriptor
                                        (label (string-append "scene/" (● step first)))
                                        (module module)
                                        (entry (● step first)))))
                           (group (create-bind-group
                                   (new BindGroupDescriptor
                                     (label "scene/unpack")
                                     (pipeline (ComputePipeline pipeline))
                                     (group 0)
                                     (entries (list (BufferEntry 0 data 0 0)
                                                    (BufferEntry 1 unpacks 0 0)
                                                    (BufferEntry 2 vertices 0 0)
                                                    (BufferEntry 3 indices 0 0)))))))
                      (set-compute-pipeline pass pipeline)
                      (set-compute-bind-group pass 0 group)
                      (dispatch-over pass (● step second))
                      (destroy (BindGroupObject group))
                      (destroy (ComputePipelineObject pipeline))))
                  (list (new Pair (first "unpack_vertices") (second vertex-count))
                        (new Pair (first "unpack_triangles") (second triangle-count))))
        (end-compute-pass pass)
        (submit (list (finish encoder)))))

    ;; Workgroups of 256 for `count` items, rows of 65535 groups.
    (define (dispatch-over (pass GpuComputePass) (count I64)) (→ Unit) (! gpu)
      (let ((groups (max 1 (quotient (+ count 255) 256))))
        (dispatch-workgroups pass
                             (i64->i32 (min groups 65535))
                             (i64->i32 (quotient (+ groups 65534) 65535))
                             1)))

    (define (storage-sized (label String) (size I64) (usage (List BufferUsage))) (→ GpuBuffer) (! gpu)
      (create-buffer (new BufferDescriptor (label label) (size (i64->i32 size)) (usage usage))))

    (define (storage-of (label String) (bytes Bytes)) (→ GpuBuffer) (! gpu)
      (let ((buffer (storage-sized label (max 16 (array-length bytes)) (list (Storage) (CopyDst)))))
        (write-buffer buffer 0 bytes)
        buffer))

    ;; ---- Textures ----

    ;; A layer for each image, at least one, each image drawn into its
    ;; first level and each next level drawn from the one before.
    (define (load-layers (images (List String)) (size I32)) (→ GpuTexture) (! fetch gpu tasks)
      (let* ((layers (create-texture (new TextureDescriptor
                                       (label "scene/layers")
                                       (width size)
                                       (height size)
                                       (layers (i64->i32 (max 1 (length images))))
                                       (mips (levels size))
                                       (format (Rgba8Unorm))
                                       (usage (list (TextureBinding) (RenderAttachment))))))
             (pipeline (layer-pipeline))
             (sampler (create-sampler (new SamplerDescriptor
                                        (label "scene/layers")
                                        (mag-filter (Linear))
                                        (min-filter (Linear))
                                        (mipmap-filter (Nearest))
                                        (address (ClampToEdge))))))
        (for-each (lambda (index)
                    (let ((image (decode-image (fetched (list-ref images index)))))
                      (fill-layer layers pipeline sampler (view-of (● image texture) 1) (i64->i32 index) size)
                      (destroy (TextureObject (● image texture)))))
                  (iota (length images)))
        layers))

    ;; Levels down to 1 by 1.
    (define (levels (size I32)) (→ I32) (if (<= size 1) 1 (+ 1 (levels (quotient size 2)))))

    ;; Each level of layer `layer` drawn from `source`, then from the level
    ;; before.
    (define (fill-layer (layers GpuTexture)
                        (pipeline GpuRenderPipeline)
                        (sampler GpuSampler)
                        (source GpuTextureView)
                        (layer I32)
                        (size I32))
      (→ Unit)
      (! gpu)
      (let ((encoder (create-command-encoder)))
        (fold-left (lambda (source level)
                     (let ((target (level-view layers layer (i64->i32 level))))
                       (draw-level encoder pipeline sampler source target)
                       (destroy (ViewObject source))
                       target))
                   source
                   (iota (i32->i64 (levels size))))
        (submit (list (finish encoder)))))

    (define (level-view (layers GpuTexture) (layer I32) (level I32)) (→ GpuTextureView) (! gpu)
      (create-view layers
                   (new TextureViewDescriptor
                     (dimension (View2d))
                     (base-mip level)
                     (mips 1)
                     (base-layer layer)
                     (layers 1))))

    (define (draw-level (encoder GpuCommandEncoder)
                        (pipeline GpuRenderPipeline)
                        (sampler GpuSampler)
                        (source GpuTextureView)
                        (target GpuTextureView))
      (→ Unit)
      (! gpu)
      (let ((group (create-bind-group (new BindGroupDescriptor
                                        (label "scene/layer")
                                        (pipeline (RenderPipeline pipeline))
                                        (group 0)
                                        (entries (list (TextureEntry 0 source) (SamplerEntry 1 sampler))))))
            (pass (begin-render-pass encoder
                                     (new RenderPassDescriptor
                                       (colors (list (Some (new ColorAttachment
                                                             (view target)
                                                             (load (Keep))
                                                             (store #t)))))
                                       (depth (None))))))
        (set-pipeline pass pipeline)
        (set-bind-group pass 0 group)
        (draw pass 3 1 0 0)
        (end-pass pass)
        (destroy (BindGroupObject group))))

    (define (layer-pipeline) (→ GpuRenderPipeline) (! gpu)
      (create-render-pipeline
       (new RenderPipelineDescriptor
         (label "scene/layer")
         (module (create-shader-module (new ShaderModuleDescriptor (label "scene/layers") (code layers-shader))))
         (vertex-entry "layer_vertex")
         (buffers (Nil))
         (fragment (Some (new FragmentState
                           (entry "layer_fragment")
                           (targets (list (Some (new ColorTarget (format (Rgba8Unorm)) (blend (None)))))))))
         (topology (TriangleList))
         (cull (CullNone))
         (depth (None)))))

    (define (repeating-sampler) (→ GpuSampler) (! gpu)
      (create-sampler (new SamplerDescriptor
                        (label "scene/repeat")
                        (mag-filter (Linear))
                        (min-filter (Linear))
                        (mipmap-filter (Linear))
                        (address (Repeat)))))

    ))
