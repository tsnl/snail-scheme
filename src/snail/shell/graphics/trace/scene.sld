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
   SurfaceMaterial
   load-scene
   release-scene
   vertex-stride
   scene-triangles)
  (import
   (snail core base)
   (snail shell gpu)
   (snail shell graphics pod)
   (snail shell graphics kernel)
   (snail shell graphics gltf)
   (only (snail shell graphics bvh) Triangles)
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

    ;; The scene's triangles as a BVH reads them: a vertex's position is
    ;; its first three words.
    (define (scene-triangles (scene Scene)) (→ Triangles)
      (new Triangles
        (positions (● scene vertices))
        (stride (i64->i32 (quotient vertex-stride 4)))
        (offset 0)
        (indices (● scene indices))
        (count (● scene triangle-count))
        (low (● scene low))
        (high (● scene high))))

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
      (let* ((gltf (drawable (read-gltf (list-ref (read (list path)) 0) (directory-of path))))
             (paths (file-paths gltf))
             (files (zip paths (read paths)))
             (buffers (map (lambda (buffer) (buffer-bytes buffer files)) (● gltf buffers)))
             (layers (load-layers gpu (map (lambda (image) (source-bytes image files buffers))
                                           (● gltf images))
                                  layer-size)))
        (on-device gpu gltf buffers layers layer-size)))

    ;; Nothing refuses once the layers are loaded, so a scene refused
    ;; leaves nothing on the device.
    (define (on-device (gpu Gpu)
                       (gltf Gltf)
                       (buffers (List Bytes))
                       (layers GpuTexture)
                       (layer-size I32))
      (→ Scene)
      (let* ((counts (placed-counts gltf))
             (geometry (unpacked gpu gltf counts buffers))
             (bounds (gltf-bounds gltf)))
        (new Scene
          (vertices (● geometry first))
          (indices (● geometry second))
          (materials (storage-of gpu "scene/materials"
                                 (pack material-shape
                                       (map surface-material (with-default (● gltf materials))))))
          (layers layers)
          (layers-view ((● gpu create-view) layers
                        (new TextureViewDescriptor
                          (dimension (View2dArray))
                          (base-mip 0)
                          (mips (levels layer-size))
                          (base-layer 0)
                          (layers 0))))
          (sampler (repeating-sampler gpu))
          (vertex-count (● counts first))
          (triangle-count (quotient (● counts second) 3))
          (low (● bounds first))
          (high (● bounds second)))))

    (define (release-scene (gpu Gpu) (scene Scene)) (→ Unit)
      (for-each (lambda (buffer) ((● gpu destroy) (BufferObject buffer)))
                (list (● scene vertices) (● scene indices) (● scene materials)))
      ((● gpu destroy) (ViewObject (● scene layers-view)))
      ((● gpu destroy) (TextureObject (● scene layers)))
      ((● gpu destroy) (SamplerObject (● scene sampler))))

    ;; ---- Sources ----

    ;; The files the scene's buffers and images name.
    (define (file-paths (gltf Gltf)) (→ (List String))
      (fold-right (lambda (source paths)
                    (match source
                      ((FileSource path) (Cons path paths))
                      (_ paths)))
                  (Nil)
                  (append (map (lambda (buffer) (● buffer source)) (● gltf buffers))
                          (● gltf images))))

    ;; A source's bytes, from the files read and, for an image in a buffer
    ;; view, the buffers.
    (define (source-bytes (source Source)
                          (files (List (Pair String Bytes)))
                          (buffers (List Bytes)))
      (→ Bytes)
      (match source
        ((FileSource path)
         (match (assoc-ref files path)
           ((Some bytes) bytes)
           ((None) (unreadable (string-append path " was not read")))))
        ((DataSource bytes) bytes)
        ((ViewSource buffer offset length)
         (let ((bytes (list-ref buffers buffer)))
           (if (<= (+ offset length) (array-length bytes))
               (subarray bytes offset (+ offset length))
               (unreadable "an image of the scene lies outside its buffer"))))))

    ;; The bytes the scene reads of a buffer, which may be the start of a
    ;; longer file.
    (define (buffer-bytes (buffer Buffer) (files (List (Pair String Bytes)))) (→ Bytes)
      (let ((bytes (source-bytes (● buffer source) files (Nil))))
        (if (< (array-length bytes) (● buffer length))
            (unreadable (string-append (match (● buffer source)
                                         ((FileSource path) path)
                                         (_ "a buffer of the scene"))
                                       " is shorter than the scene says"))
            (subarray bytes 0 (● buffer length)))))

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
              (storage-buffer gpu "scene/vertices" (* vertex-stride (● counts first)) (Nil)))
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
