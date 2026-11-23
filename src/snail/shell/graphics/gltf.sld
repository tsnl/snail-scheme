;; A glTF 2.0 scene, a .gltf file's JSON or a .glb file, read into what
;; drawing and tracing it need: the buffers and images it names, each
;; primitive's accessors as byte offsets into its buffers laid end to end,
;; its materials, and each primitive placed by the node hierarchy of the
;; default scene. The buffers' bytes are not read here: they go to the
;; device whole, and a compute pass unpacks each accessor ((snail shell
;; graphics trace scene)). A scene that cannot be read stops the reading
;; with why: one that is not JSON, names an item it does not have, or
;; stores its geometry compressed.
;;
;; Read: triangle primitives, POSITION, NORMAL, TEXCOORD_0 and TANGENT,
;; indices of any width, metallic-roughness materials with their base
;; color, metal-roughness, normal and emissive textures, alpha modes, and
;; KHR_materials_emissive_strength. Buffers and images are files named by
;; URIs relative to the scene's, base64 data: URIs, a GLB file's binary
;; chunk, or for an image a buffer view; sparse accessors, other texture
;; coordinate sets and cameras are not read, nor
;; geometry compressed by Draco or meshopt.
(define-library (snail shell graphics gltf)
  (export
   Gltf
   Buffer
   Source
   FileSource
   DataSource
   ViewSource
   unreadable
   attempt-reading
   Attribute
   Primitive
   Primitive-material-set
   Gltf-buffers-set
   Buffer-source-set
   Placed-matrix-set
   Gltf-placed-set
   Material
   Placed
   read-gltf
   append-gltf
   Document
   read-document
   gltf-ref
   gltf-items
   gltf-text
   gltf-integer
   gltf-numbers
   source-bytes
   buffer-bytes
   scene-materials
   gltf-bounds
   gltf-scaled
   uri-path)
  (import
   (snail core base)
   (snail shell utf8)
   (snail shell json)
   (snail shell json read))
  (begin

    ;; ---- The scene ----

    ;; The buffers and the size of them laid end to end; the images'
    ;; sources; the materials; and each primitive of the default scene
    ;; with the matrix that places it.
    (record Gltf
      ((buffers (List Buffer))
       (size I64)
       (images (List Source))
       (materials (List Material))
       (placed (List Placed))))

    ;; A buffer: where its bytes are, where it starts once the buffers are
    ;; laid end to end, each from a multiple of 4, and how many bytes the
    ;; scene reads of it.
    (record Buffer
      ((source Source)
       (start I64)
       (length I64)))

    ;; Where a buffer's or an image's bytes are: a file beside the scene,
    ;; its path the URI relative to the scene's directory; bytes the scene
    ;; holds, a data: URI's or a .glb file's binary chunk; or bytes of a
    ;; buffer, from an offset.
    (enum Source
      (FileSource ((path String)))
      (DataSource ((bytes Bytes)))
      (ViewSource ((buffer I64) (offset I64) (length I64))))

    ;; An accessor: where its first element starts in the laid-out buffers,
    ;; the bytes from one element to the next, its component type (5120 to
    ;; 5126, glTF's GL constants), whether integers are normalized, and how
    ;; many elements it has.
    (record Attribute
      ((offset I64)
       (stride I64)
       (width I64)
       (component I64)
       (normalized Bool)
       (count I64)))

    ;; Its corners, from POSITION's min and max, are in the mesh's space.
    (record Primitive
      ((positions Attribute)
       (normals (Option Attribute))
       (uvs (Option Attribute))
       (tangents (Option Attribute))
       (joints (Option Attribute))
       (weights (Option Attribute))
       (indices (Option Attribute))
       (material I64)
       (low (List F64))
       (high (List F64))))

    ;; A texture is the index of its image, -1 when there is none. Alpha
    ;; is 0 for OPAQUE, 1 for MASK and 2 for BLEND.
    (record Material
      ((base-color (List F64))
       (base-texture I64)
       (metallic F64)
       (roughness F64)
       (metal-rough-texture I64)
       (normal-texture I64)
       (normal-scale F64)
       (emissive (List F64))
       (emissive-texture I64)
       (alpha I64)
       (alpha-cutoff F64)
       (double-sided Bool)))

    ;; A primitive, and the column-major matrix from its mesh to the world.
    (record Placed
      ((node I64)
       (primitive Primitive)
       (matrix (List F64))))

    ;; ---- Reading ----

    ;; A scene that cannot be read stops being read: nothing after
    ;; `unreadable` runs, and `attempt-reading` answers why. Nothing
    ;; resumes a suspension to the reading prompt, so it only unwinds.
    (define unreading (→ (Prompt String Never)) (make-prompt))

    (define (unreadable (why String)) (→ A) (∀ (A))
      (absurd (suspend unreading why)))

    (define (attempt-reading (work (Fn → T))) (→ (Result T String)) (∀ (T))
      (with-prompt unreading (lambda () (Ok (work))) (lambda (why resume) (Err why))))

    ;; The scene in `file`, a .gltf or a .glb file, whose URIs are relative
    ;; to `base`, the URL of the directory holding it, ending in a slash.
    (define (read-gltf (file Bytes) (base String)) (→ Gltf)
      (● (read-document file base) scene))

    (record Document
      ((scene Gltf)
       (json Json)
       (accessors (Array Attribute))))
    (define (read-document (file Bytes) (base String)) (→ Document)
      (let ((chunks (file-chunks file)))
        (match (utf8->string (● chunks first))
          ((Ok text)
           (match (string->json text)
             ((Some json) (gltf-of json base (● chunks second)))
             ((None) (unreadable "the scene is not JSON"))))
          ((Err _) (unreadable "the scene is not UTF-8")))))

    (define (gltf-of (json Json) (base String) (chunk Bytes)) (→ Document)
      (refuse-compressed json)
      (let* ((buffers (list->array (buffers-of json base chunk)))
             (views (list->array (gltf-items json "bufferViews")))
             (accessors (list->array (map (lambda (accessor) (accessor-of accessor views buffers))
                                          (gltf-items json "accessors"))))
             (bounds (list->array (map accessor-bounds (gltf-items json "accessors"))))
             (meshes (list->array (map (lambda (mesh) (primitives-of mesh accessors bounds))
                                       (gltf-items json "meshes"))))
             (images (list->array (map (lambda (texture) (gltf-integer texture "source" -1))
                                       (gltf-items json "textures")))))
        (new Document (json json) (accessors accessors) (scene (new Gltf
                                                                 (buffers (array->list buffers))
                                                                 (size
                                                                  (fold-left (lambda (size buffer)
                                                                               (aligned
                                                                                (+ (● buffer start)
                                                                                   (● buffer
                                                                                      length))))
                                                                             0
                                                                             (array->list buffers)))
                                                                 (images (map (lambda (image)
                                                                                (image-source image
                                                                                              views
                                                                                              buffers
                                                                                              base))
                                                                              (gltf-items json
                                                                                          "images")))
                                                                 (materials
                                                                  (map (lambda (material)
                                                                         (material-of material
                                                                                      images))
                                                                       (gltf-items json
                                                                                   "materials")))
                                                                 (placed
                                                                  (scene-placed json meshes)))))))

    ;; Compressed geometry is in no accessor's bytes, so a scene that needs
    ;; it has nothing to draw.
    (define (refuse-compressed (json Json)) (→ Unit)
      (for-each (lambda (extension)
                  (match extension
                    ((JsonString name)
                     (when (member? name
                                    (list "KHR_draco_mesh_compression" "EXT_meshopt_compression"))
                       (unreadable (string-append "the scene needs " name ", which is not read"))))
                    (_ (unit))))
                (gltf-items json "extensionsRequired")))

    ;; The item a scene names by `index`.
    (define (gltf-ref (items (Array T)) (index I64) (kind String)) (→ T) (∀ (T))
      (if (and (>= index 0) (< index (array-length items)))
          (array-ref items index)
          (unreadable (string-append "the scene has no " kind " " (show index)))))

    ;; ---- Buffers and images ----

    ;; Each buffer after the one before it. A buffer without a URI is the
    ;; .glb file's binary chunk.
    (define (buffers-of (json Json) (base String) (chunk Bytes)) (→ (List Buffer))
      (reverse
       (fold-left (lambda (laid buffer)
                    (Cons (new Buffer
                            (source (match (uri-source buffer base)
                                      ((Some source) source)
                                      ((None) (DataSource chunk))))
                            (start (match laid
                                     ((Cons last _) (aligned (+ (● last start) (● last length))))
                                     ((Nil) 0)))
                            (length (gltf-integer buffer "byteLength" 0)))
                          laid))
                  (Nil)
                  (gltf-items json "buffers"))))

    (define (aligned (size I64)) (→ I64) (* 4 (quotient (+ size 3) 4)))

    (define (uri-source (holder Json) (base String)) (→ (Option Source))
      (match (json-member holder "uri")
        ((Some (JsonString uri))
         (Some (if (and (>= (string-length uri) 5) (string=? (substring uri 0 5) "data:"))
                   (DataSource (base64-bytes uri))
                   (FileSource (string-append base (uri-path uri))))))
        (_ (None))))

    (define (image-source (image Json) (views (Array Json)) (buffers (Array Buffer)) (base String))
      (→ Source)
      (match (json-member image "bufferView")
        ((Some (JsonInteger index))
         (let* ((view (gltf-ref views index "buffer view")) (buffer (gltf-integer view "buffer" 0)))
           (gltf-ref buffers buffer "buffer")
           (ViewSource buffer
                       (gltf-integer view "byteOffset" 0)
                       (gltf-integer view "byteLength" 0))))
        (_ (match (uri-source image base)
             ((Some source) source)
             ((None) (unreadable "an image of the scene names no file"))))))

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

    ;; ---- Accessors ----

    ;; An accessor starts where its buffer does, then its view, then
    ;; itself; a view without a stride packs its elements. One with a
    ;; view lies within its buffer; one without is read as the first
    ;; view's bytes, though glTF means zeros.
    (define (accessor-of (accessor Json) (views (Array Json)) (buffers (Array Buffer)))
      (→ Attribute)
      (let* ((view (gltf-ref views (gltf-integer accessor "bufferView" 0) "buffer view"))
             (buffer (gltf-ref buffers (gltf-integer view "buffer" 0) "buffer"))
             (component (gltf-integer accessor "componentType" 5126))
             (packed
              (* (component-size component) (element-count (gltf-text accessor "type" "SCALAR"))))
             (stride (match (gltf-integer view "byteStride" 0)
                       (0 packed)
                       (stride stride)))
             (count (gltf-integer accessor "count" 0))
             (offset (+ (gltf-integer view "byteOffset" 0) (gltf-integer accessor "byteOffset" 0))))
        (match (json-member accessor "bufferView")
          ((Some _)
           (let ((v (gltf-integer view "byteOffset" 0)) (n (gltf-integer view "byteLength" 0)))
             (unless (and (>= v 0) (>= n 0) (<= (+ v n) (● buffer length))
                          (>= offset v) (>= count 1) (>= stride packed)
                          (>= (- (+ v n) offset) packed)
                          (<= (- count 1) (quotient (- (- (+ v n) offset) packed) stride)))
               (unreadable "an accessor of the scene lies outside its buffer"))))
          ((None) (unit)))
        (new Attribute
          (offset (+ (● buffer start) offset))
          (stride stride)
          (width (element-count (gltf-text accessor "type" "SCALAR")))
          (component component)
          (normalized (bool-or accessor "normalized" #f))
          (count count))))

    (define (component-size (component I64)) (→ I64)
      (match component
        (5120 1)
        (5121 1)
        (5122 2)
        (5123 2)
        (_ 4)))

    (define (element-count (type String)) (→ I64)
      (cond ((string=? type "VEC2") 2)
            ((string=? type "VEC3") 3)
            ((string=? type "VEC4") 4)
            ((string=? type "MAT4") 16)
            (else 1)))

    ;; ---- Meshes ----

    ;; A mesh's triangle primitives; points and lines are left out.
    (define (primitives-of (mesh Json)
                           (accessors (Array Attribute))
                           (bounds (Array (Pair (List F64) (List F64)))))
      (→ (List Primitive))
      (fold-right (lambda (primitive rest)
                    (if (= (gltf-integer primitive "mode" 4) 4)
                        (match (primitive-of primitive accessors bounds)
                          ((Some read) (Cons read rest))
                          ((None) rest))
                        rest))
                  (Nil)
                  (gltf-items mesh "primitives")))

    (define (primitive-of (primitive Json)
                          (accessors (Array Attribute))
                          (bounds (Array (Pair (List F64) (List F64)))))
      (→ (Option Primitive))
      (let* ((attributes (member-or primitive "attributes"))
             (accessor (lambda ((holder Json) (name String)) (→ (Option Attribute))
                         (match (json-member holder name)
                           ((Some (JsonInteger index)) (Some (gltf-ref accessors index "accessor")))
                           (_ (None))))))
        (match (json-member attributes "POSITION")
          ((Some (JsonInteger position))
           (Some (new Primitive
                   (positions (gltf-ref accessors position "accessor"))
                   (normals (accessor attributes "NORMAL"))
                   (uvs (accessor attributes "TEXCOORD_0"))
                   (tangents (accessor attributes "TANGENT"))
                   (joints (accessor attributes "JOINTS_0"))
                   (weights (accessor attributes "WEIGHTS_0"))
                   (indices (accessor primitive "indices"))
                   (material (gltf-integer primitive "material" -1))
                   (low (● (array-ref bounds position) first))
                   (high (● (array-ref bounds position) second)))))
          (_ (None)))))

    ;; ---- Materials ----

    ;; A texture reference's image, -1 when it has none.
    (define (material-of (material Json) (images (Array I64))) (→ Material)
      (let* ((pbr (member-or material "pbrMetallicRoughness"))
             (image (lambda ((holder Json) (name String)) (→ I64)
                      (let ((texture (gltf-integer (member-or holder name) "index" -1)))
                        (if (< texture 0) -1 (gltf-ref images texture "texture")))))
             (strength (number-or (member-or (member-or material "extensions")
                                             "KHR_materials_emissive_strength")
                                  "emissiveStrength"
                                  1.0)))
        (new Material
          (base-color (gltf-numbers pbr "baseColorFactor" (list 1.0 1.0 1.0 1.0)))
          (base-texture (image pbr "baseColorTexture"))
          (metallic (number-or pbr "metallicFactor" 1.0))
          (roughness (number-or pbr "roughnessFactor" 1.0))
          (metal-rough-texture (image pbr "metallicRoughnessTexture"))
          (normal-texture (image material "normalTexture"))
          (normal-scale (number-or (member-or material "normalTexture") "scale" 1.0))
          (emissive (map (lambda (channel) (* channel strength))
                         (gltf-numbers material "emissiveFactor" (list 0.0 0.0 0.0))))
          (emissive-texture (image material "emissiveTexture"))
          (alpha (let ((mode (gltf-text material "alphaMode" "OPAQUE")))
                   (cond ((string=? mode "MASK") 1)
                         ((string=? mode "BLEND") 2)
                         (else 0))))
          (alpha-cutoff (number-or material "alphaCutoff" 0.5))
          (double-sided (bool-or material "doubleSided" #f)))))

    (define default-material (→ Material) (new Material
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
    (define (scene-materials (gltf Gltf)) (→ (List Material))
      (if (null? (● gltf materials)) (list default-material) (● gltf materials)))

    ;; ---- Combining models ----

    ;; The second model's accessors, image views and material references move
    ;; into the first model's address space. Both models keep their placements.
    (define (append-gltf (a Gltf) (b Gltf)) (→ Gltf)
      (let* ((offset (● a size)) (first (length (● a buffers))) (images (length (● a images)))
             (mats-a (model-materials a)) (mats-b (model-materials b))
             (rebase (lambda ((p Placed)) (→ Placed)
                       (Placed-primitive-set p
                                             (shift-primitive (● p primitive)
                                                              offset
                                                              (length mats-a)
                                                              (length mats-b))))))
        (new Gltf (size (+ offset (● b size)))
             (buffers (append (● a buffers)
                              (map (lambda (buf) (Buffer-start-set buf (+ offset (● buf start))))
                                   (● b buffers))))
             (images (append (● a images)
                             (map (lambda (s)
                                    (match s
                                      ((ViewSource i at n) (ViewSource (+ first i) at n))
                                      (_ s)))
                                  (● b images))))
             (materials (append mats-a (map (lambda (m) (shift-material m images)) mats-b)))
             (placed (append (map (lambda (p)
                                    (Placed-primitive-set p
                                                          (shift-primitive (● p primitive)
                                                                           0
                                                                           0
                                                                           (length mats-a))))
                                  (● a placed))
                             (map rebase (● b placed)))))))

    ;; glTF's omitted material is a separate default, even when materials exist.
    (define (model-materials (g Gltf)) (→ (List Material))
      (if (and (not (null? (● g materials)))
               (any? (lambda (p) (< (● p primitive material) 0)) (● g placed)))
          (append (● g materials) (list default-material))
          (scene-materials g)))
    (define (shift-material (m Material) (n I64)) (→ Material)
      (let ((shift (lambda ((i I64)) (→ I64) (if (< i 0) i (+ i n)))))
        (Material-emissive-texture-set
         (Material-normal-texture-set
          (Material-metal-rough-texture-set (Material-base-texture-set m (shift (● m base-texture)))
                                            (shift (● m metal-rough-texture)))
          (shift (● m normal-texture))) (shift (● m emissive-texture)))))
    (define (shift-primitive (p Primitive) (n I64) (first I64) (count I64)) (→ Primitive)
      (let* ((at (lambda ((a Attribute)) (→ Attribute) (Attribute-offset-set a (+ n (● a offset)))))
             (maybe (lambda ((a (Option Attribute)))
                      (→ (Option Attribute))
                      (match a ((Some v) (Some (at v))) ((None) (None))))))
        (new Primitive (positions (at (● p positions))) (normals (maybe (● p normals)))
             (uvs (maybe (● p uvs)))
             (tangents (maybe (● p tangents)))
             (indices (maybe (● p indices)))
             (weights (maybe (● p weights))) (joints (maybe (● p joints)))
             (material (+ first (if (< (● p material) 0) (- count 1) (● p material))))
             (low (● p low)) (high (● p high)))))

    ;; ---- Nodes ----

    ;; Each primitive under the default scene's roots, placed by the
    ;; matrices of the nodes above it.
    (define (scene-placed (json Json) (meshes (Array (List Primitive))))
      (→ (List Placed))
      (let* ((scenes (list->array (gltf-items json "scenes")))
             (roots (if (= (array-length scenes) 0)
                        (Nil)
                        (gltf-items (gltf-ref scenes (gltf-integer json "scene" 0) "scene")
                                    "nodes")))
             (nodes (list->array (gltf-items json "nodes"))))
        (concatenate
         (map (lambda (root) (node-placed nodes meshes (json-index root) identity 0)) roots))))

    ;; A node deeper than there are nodes is under itself.
    (define (node-placed (nodes (Array Json))
                         (meshes (Array (List Primitive)))
                         (index I64)
                         (parent (List F64))
                         (depth I64))
      (→ (List Placed))
      (when (> depth (array-length nodes))
        (unreadable "the scene's nodes form a loop"))
      (let* ((node (gltf-ref nodes index "node"))
             (matrix (multiply parent (local-matrix node)))
             (own (match (json-member node "mesh")
                    ((Some (JsonInteger mesh))
                     (map (lambda (primitive)
                            (new Placed (node index) (primitive primitive) (matrix matrix)))
                          (gltf-ref meshes mesh "mesh")))
                    (_ (Nil)))))
        (append own
                (concatenate
                 (map (lambda (child)
                        (node-placed nodes meshes (json-index child) matrix (+ depth 1)))
                      (gltf-items node "children"))))))

    (define (accessor-bounds (accessor Json)) (→ (Pair (List F64) (List F64)))
      (new Pair
        (first (gltf-numbers accessor "min" (list 0.0 0.0 0.0)))
        (second (gltf-numbers accessor "max" (list 0.0 0.0 0.0)))))

    (define (json-index (value Json)) (→ I64)
      (match value
        ((JsonInteger index) index)
        (_ 0)))

    ;; A node's `matrix`, or its translation, rotation and scale composed.
    (define (local-matrix (node Json)) (→ (List F64))
      (match (json-member node "matrix")
        ((Some _) (gltf-numbers node "matrix" identity))
        ((None)
         (trs (gltf-numbers node "translation" (list 0.0 0.0 0.0))
              (gltf-numbers node "rotation" (list 0.0 0.0 0.0 1.0))
              (gltf-numbers node "scale" (list 1.0 1.0 1.0))))))

    ;; Columns of the rotation of quaternion x, y, z, w, scaled, then the
    ;; translation.
    (define (trs (t (List F64)) (q (List F64)) (s (List F64))) (→ (List F64))
      (let ((x (list-ref q 0)) (y (list-ref q 1)) (z (list-ref q 2)) (w (list-ref q 3)))
        (concatenate (list (column (- 1.0 (* 2.0 (+ (* y y) (* z z))))
                                   (* 2.0 (+ (* x y) (* z w)))
                                   (* 2.0 (- (* x z) (* y w)))
                                   (list-ref s 0))
                           (column (* 2.0 (- (* x y) (* z w)))
                                   (- 1.0 (* 2.0 (+ (* x x) (* z z))))
                                   (* 2.0 (+ (* y z) (* x w)))
                                   (list-ref s 1))
                           (column (* 2.0 (+ (* x z) (* y w)))
                                   (* 2.0 (- (* y z) (* x w)))
                                   (- 1.0 (* 2.0 (+ (* x x) (* y y))))
                                   (list-ref s 2))
                           (list (list-ref t 0) (list-ref t 1) (list-ref t 2) 1.0)))))

    (define (column (a F64) (b F64) (c F64) (scale F64)) (→ (List F64))
      (list (* a scale) (* b scale) (* c scale) 0.0))

    (define identity
      (→ (List F64))
      (list 1.0 0.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 0.0 1.0))

    ;; Column-major: element row r of column c is at 4c + r.
    (define (multiply (a (List F64)) (b (List F64))) (→ (List F64))
      (let ((a (list->array a)) (b (list->array b)))
        (map (lambda (index)
               (let ((c (quotient index 4)) (r (remainder index 4)))
                 (fold-left (lambda (sum k)
                              (+ sum (* (array-ref a (+ (* k 4) r)) (array-ref b (+ (* c 4) k)))))
                            0.0
                            (iota 4))))
             (iota 16))))

    ;; ---- URIs ----

    ;; A relative URI as the name of the file it refers to: each %XX
    ;; escape replaced by its byte, the bytes read as UTF-8, and `./`
    ;; segments dropped. A query string's value is decoded the same way.
    (define (uri-path (uri String)) (→ String)
      (match (utf8->string (list->array (unescaped-bytes (array->list (string->utf8 uri)))))
        ((Ok text) (without-dot-segments text))
        ((Err _) uri)))

    (define (unescaped-bytes (bytes (List U8))) (→ (List U8))
      (match bytes
        ((Cons percent (Cons high (Cons low rest)))
         (match (escape (u8->i32 percent) (u8->i32 high) (u8->i32 low))
           ((Some byte) (Cons byte (unescaped-bytes rest)))
           ((None) (Cons percent (unescaped-bytes (Cons high (Cons low rest)))))))
        ((Cons byte rest) (Cons byte (unescaped-bytes rest)))
        ((Nil) (Nil))))

    (define (escape (percent I32) (high I32) (low I32)) (→ (Option U8))
      (if (= percent 37)
          (match (hex-digit high)
            ((Some h) (match (hex-digit low)
                        ((Some l) (Some (i32->u8 (+ (* 16 h) l))))
                        ((None) (None))))
            ((None) (None)))
          (None)))

    (define (hex-digit (code I32)) (→ (Option I32))
      (cond ((and (>= code 48) (<= code 57)) (Some (- code 48)))
            ((and (>= code 65) (<= code 70)) (Some (- code 55)))
            ((and (>= code 97) (<= code 102)) (Some (- code 87)))
            (else (None))))

    (define (without-dot-segments (path String)) (→ String)
      (if (and (>= (string-length path) 2) (string=? (substring path 0 2) "./"))
          (without-dot-segments (substring path 2 (string-length path)))
          path))

    ;; A data: URI's bytes, base64 after its comma: four letters for three
    ;; bytes, the last group short by the `=` that pad it.
    (define (base64-bytes (uri String)) (→ Bytes)
      (let* ((from (match (string-index uri #\,)
                     ((Some at) (+ at 1))
                     ((None) (string-length uri))))
             (letters (list->array (filter (lambda (char) (not (char=? char #\=)))
                                           (string->list
                                            (substring uri from (string-length uri))))))
             (sextet (lambda ((index I64)) (→ I64) (letter-value (array-ref letters index)))))
        (array-generate (quotient (* 3 (array-length letters)) 4)
                        (lambda (index)
                          (let* ((at (* 4 (quotient index 3)))
                                 (k (remainder index 3)))
                            (i32->u8
                             (i64->i32 (remainder (+ (* (sextet (+ at k)) (expt-2 (+ 2 (* 2 k))))
                                                     (quotient (sextet (+ at (+ k 1)))
                                                               (expt-2 (- 4 (* 2 k)))))
                                                  256))))))))

    (define (letter-value (char Char)) (→ I64)
      (let ((code (char->integer char)))
        (cond ((and (>= code 65) (<= code 90)) (- code 65))
              ((and (>= code 97) (<= code 122)) (- code 71))
              ((and (>= code 48) (<= code 57)) (+ code 4))
              ((= code 43) 62)
              (else 63))))

    ;; ---- GLB ----

    ;; A scene file's JSON and its binary chunk. A .glb file is a 12-byte
    ;; header starting "glTF", then chunks of a length, a type and that
    ;; many bytes: the JSON, then the binary chunk if it has one. Any other
    ;; file is the JSON, with an empty chunk.
    (define (file-chunks (file Bytes)) (→ (Pair Bytes Bytes))
      (if (and (>= (array-length file) 20) (= (word file 0) 1179937895))
          (let* ((json-end (+ 20 (word file 12))) (bin (+ 8 json-end)))
            (new Pair
              (first (chunk file 20 json-end))
              (second (if (<= bin (array-length file))
                          (chunk file bin (+ bin (word file json-end)))
                          (make-array 0 (i32->u8 0))))))
          (new Pair (first file) (second (make-array 0 (i32->u8 0))))))

    (define (chunk (file Bytes) (from I64) (to I64)) (→ Bytes)
      (if (<= to (array-length file))
          (subarray file from to)
          (unreadable "the .glb file is cut short")))

    ;; The little-endian 32-bit word at `at`.
    (define (word (bytes Bytes) (at I64)) (→ I64)
      (fold-right
       (lambda (index value) (+ (i32->i64 (u8->i32 (array-ref bytes (+ at index)))) (* 256 value)))
       0
       (iota 4)))

    ;; ---- Bounds ----

    ;; The corners of the box around every placed primitive, from its
    ;; positions' bounds.
    (define (gltf-bounds (gltf Gltf)) (→ (Pair (List F64) (List F64)))
      (fold-left (lambda (box placed)
                   (fold-left (lambda (box corner)
                                (new Pair
                                  (first (pairwise min (● box first) corner))
                                  (second (pairwise max (● box second) corner))))
                              box
                              (placed-corners placed)))
                 (new Pair (first (list 1e30 1e30 1e30)) (second (list -1e30 -1e30 -1e30)))
                 (● gltf placed)))

    ;; The scene made `factor` times larger about the origin: each
    ;; placement's matrix with its first three rows scaled.
    (define (gltf-scaled (gltf Gltf) (factor F64)) (→ Gltf)
      (Gltf-placed-set gltf
                       (map (lambda (placed)
                              (Placed-matrix-set placed
                                                 (map (lambda (index)
                                                        (let ((x
                                                               (list-ref (● placed matrix) index)))
                                                          (if (< (remainder index 4) 3)
                                                              (* factor x)
                                                              x)))
                                                      (iota 16))))
                            (● gltf placed))))

    (define (pairwise (f (Fn F64 F64 → F64)) (a (List F64)) (b (List F64))) (→ (List F64))
      (map (lambda (index) (f (list-ref a index) (list-ref b index))) (iota (length a))))

    (define (placed-corners (placed Placed)) (→ (List (List F64)))
      (let ((low (● placed primitive low)) (high (● placed primitive high)))
        (map (lambda (corner)
               (transform (● placed matrix)
                          (map (lambda (axis)
                                 (if (= (remainder (quotient corner (expt-2 axis)) 2) 0)
                                     (list-ref low axis)
                                     (list-ref high axis)))
                               (iota 3))))
             (iota 8))))

    (define (expt-2 (n I64)) (→ I64) (if (= n 0) 1 (* 2 (expt-2 (- n 1)))))

    (define (transform (m (List F64)) (p (List F64))) (→ (List F64))
      (map (lambda (r)
             (+ (list-ref m (+ 12 r))
                (fold-left (lambda (sum c) (+ sum (* (list-ref m (+ (* c 4) r)) (list-ref p c))))
                           0.0
                           (iota 3))))
           (iota 3)))

    ;; ---- JSON ----

    (define (member-or (json Json) (name String)) (→ Json)
      (match (json-member json name)
        ((Some value) value)
        ((None) (JsonObject (Nil)))))

    (define (gltf-items (json Json) (name String)) (→ (List Json))
      (match (json-member json name)
        ((Some (JsonArray values)) values)
        (_ (Nil))))

    (define (gltf-integer (json Json) (name String) (default I64)) (→ I64)
      (match (json-member json name)
        ((Some (JsonInteger value)) value)
        (_ default)))

    (define (number-or (json Json) (name String) (default F64)) (→ F64)
      (match (json-member json name)
        ((Some value) (number-of value default))
        ((None) default)))

    (define (number-of (value Json) (default F64)) (→ F64)
      (match value
        ((JsonInteger value) (i64->f64 value))
        ((JsonNumber value) value)
        (_ default)))

    ;; As many numbers as the default has, or the default.
    (define (gltf-numbers (json Json) (name String) (default (List F64))) (→ (List F64))
      (match (json-member json name)
        ((Some (JsonArray values))
         (if (= (length values) (length default))
             (map (lambda (value) (number-of value 0.0)) values)
             default))
        (_ default)))

    (define (gltf-text (json Json) (name String) (default String)) (→ String)
      (match (json-member json name)
        ((Some (JsonString value)) value)
        (_ default)))

    (define (bool-or (json Json) (name String) (default Bool)) (→ Bool)
      (match (json-member json name)
        ((Some (JsonBool value)) value)
        (_ default)))

    ))
