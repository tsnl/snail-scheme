;; A glTF 2.0 scene's JSON read into what drawing and tracing it need: the
;; buffers and images it names, each primitive's accessors as byte
;; offsets into its buffers laid end to end, its materials, and each
;; primitive placed by the node hierarchy of the default scene. The bytes
;; themselves are not read here: the buffers go to the device whole, and a
;; compute pass unpacks each accessor ((snail shell graphics scene)).
;;
;; Read: triangle primitives, POSITION, NORMAL, TEXCOORD_0 and TANGENT,
;; indices of any width, metallic-roughness materials with their base
;; color, metal-roughness, normal and emissive textures, alpha modes, and
;; KHR_materials_emissive_strength. Buffers and images are files named by
;; URIs relative to the scene's, base64 data: URIs, a GLB file's binary
;; chunk, or for an image a buffer view; sparse accessors, other texture
;; coordinate sets, cameras, skins and animation are not read.
(define-library (snail shell graphics gltf)
  (export
   Gltf
   Source
   FileSource
   DataSource
   ChunkSource
   ViewSource
   glb-chunks
   Attribute
   Primitive
   Material
   Placed
   read-gltf
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

    ;; The buffers' sources and where each starts once they are laid end
    ;; to end, each from a multiple of 4; the images' sources; the materials; each
    ;; mesh's primitives; and each primitive of the default scene with the
    ;; matrix that places it. Accessors' bounds are read where POSITION names
    ;; them, as its corners.
    (record Gltf
      ((buffers (List Source))
       (size I64)
       (images (List Source))
       (materials (List Material))
       (placed (List Placed))))

    ;; Where a buffer's or an image's bytes are: a file beside the scene,
    ;; its path the URI relative to the scene's directory; a data: URI's
    ;; bytes; the binary chunk of the GLB file holding the scene; or bytes
    ;; of a buffer, from an offset.
    (enum Source
      (FileSource ((path String)))
      (DataSource ((bytes Bytes)))
      (ChunkSource)
      (ViewSource ((buffer I64) (offset I64) (length I64))))

    ;; An accessor: where its first element starts in the laid-out buffers,
    ;; the bytes from one element to the next, its component type (5120 to
    ;; 5126, glTF's GL constants), whether integers are normalized, and how
    ;; many elements it has.
    (record Attribute
      ((offset I64)
       (stride I64)
       (component I64)
       (normalized Bool)
       (count I64)))

    ;; Its corners, from POSITION's min and max, are in the mesh's space.
    (record Primitive
      ((positions Attribute)
       (normals (Option Attribute))
       (uvs (Option Attribute))
       (tangents (Option Attribute))
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
      ((primitive Primitive)
       (matrix (List F64))))

    ;; The scene in `text`, whose URIs are relative to `base`, the URL of
    ;; the directory holding it, ending in a slash.
    (define (read-gltf (text String) (base String)) (→ (Result Gltf String))
      (match (string->json text)
        ((Some json) (Ok (gltf-of json base)))
        ((None) (Err "not JSON"))))

    (define (gltf-of (json Json) (base String)) (→ Gltf)
      (let* ((starts (buffer-starts (items json "buffers")))
             (views
              (list->array (map (lambda (view) (view-of view starts)) (items json "bufferViews"))))
             (accessors (list->array (map (lambda (accessor) (accessor-of accessor views))
                                          (items json "accessors"))))
             (bounds (list->array (map accessor-bounds (items json "accessors"))))
             (meshes (list->array (map (lambda (mesh) (primitives-of mesh accessors bounds))
                                       (items json "meshes"))))
             (images (list->array (map (lambda (texture) (integer-or texture "source" -1))
                                       (items json "textures")))))
        (new Gltf
          (buffers (map (lambda (buffer) (uri-source buffer base)) (items json "buffers")))
          (size (fold-left max 0 starts))
          (images (map (lambda (image) (image-source image (items json "bufferViews") base))
                       (items json "images")))
          (materials
           (map (lambda (material) (material-of material images)) (items json "materials")))
          (placed (scene-placed json meshes)))))

    ;; A buffer without a URI is a GLB file's binary chunk.
    (define (uri-source (holder Json) (base String)) (→ Source)
      (match (json-member holder "uri")
        ((Some (JsonString uri))
         (if (and (>= (string-length uri) 5) (string=? (substring uri 0 5) "data:"))
             (DataSource (base64-bytes uri))
             (FileSource (string-append base (uri-path uri)))))
        (_ (ChunkSource))))

    (define (image-source (image Json) (views (List Json)) (base String)) (→ Source)
      (match (json-member image "bufferView")
        ((Some (JsonInteger index))
         (let ((view (list-ref views index)))
           (ViewSource (integer-or view "buffer" 0)
                       (integer-or view "byteOffset" 0)
                       (integer-or view "byteLength" 0))))
        (_ (uri-source image base))))

    ;; Where each buffer starts, and after the last, where they end.
    (define (buffer-starts (buffers (List Json))) (→ (List I64))
      (reverse (fold-left (lambda (starts buffer)
                            (match starts
                              ((Cons last _)
                               (Cons (+ last (aligned (integer-or buffer "byteLength" 0))) starts))
                              ((Nil) starts)))
                          (list 0)
                          buffers)))

    (define (aligned (size I64)) (→ I64) (* 4 (quotient (+ size 3) 4)))

    ;; ---- Accessors ----

    ;; A buffer view: where it starts in the laid-out buffers, and its
    ;; stride, 0 when its elements are packed.
    (record View
      ((start I64)
       (stride I64)))

    (define (view-of (view Json) (starts (List I64))) (→ View)
      (new View
        (start (+ (list-ref starts (integer-or view "buffer" 0)) (integer-or view "byteOffset" 0)))
        (stride (integer-or view "byteStride" 0))))

    (define (accessor-of (accessor Json) (views (Array View))) (→ Attribute)
      (let* ((view (array-ref views (integer-or accessor "bufferView" 0)))
             (component (integer-or accessor "componentType" 5126))
             (packed
              (* (component-size component) (element-count (text-or accessor "type" "SCALAR")))))
        (new Attribute
          (offset (+ (● view start) (integer-or accessor "byteOffset" 0)))
          (stride (if (= (● view stride) 0) packed (● view stride)))
          (component component)
          (normalized (bool-or accessor "normalized" #f))
          (count (integer-or accessor "count" 0)))))

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
                    (if (= (integer-or primitive "mode" 4) 4)
                        (match (primitive-of primitive accessors bounds)
                          ((Some read) (Cons read rest))
                          ((None) rest))
                        rest))
                  (Nil)
                  (items mesh "primitives")))

    (define (primitive-of (primitive Json)
                          (accessors (Array Attribute))
                          (bounds (Array (Pair (List F64) (List F64)))))
      (→ (Option Primitive))
      (let* ((attributes (member-or primitive "attributes"))
             (attribute (lambda ((name String)) (→ (Option Attribute))
                          (match (json-member attributes name)
                            ((Some (JsonInteger index)) (Some (array-ref accessors index)))
                            (_ (None))))))
        (match (json-member attributes "POSITION")
          ((Some (JsonInteger position))
           (Some (new Primitive
                   (positions (array-ref accessors position))
                   (normals (attribute "NORMAL"))
                   (uvs (attribute "TEXCOORD_0"))
                   (tangents (attribute "TANGENT"))
                   (indices (match (json-member primitive "indices")
                              ((Some (JsonInteger index)) (Some (array-ref accessors index)))
                              (_ (None))))
                   (material (integer-or primitive "material" -1))
                   (low (● (array-ref bounds position) first))
                   (high (● (array-ref bounds position) second)))))
          (_ (None)))))

    ;; ---- Materials ----

    ;; A texture reference's image, -1 when it has none.
    (define (material-of (material Json) (images (Array I64))) (→ Material)
      (let* ((pbr (member-or material "pbrMetallicRoughness"))
             (image (lambda ((holder Json) (name String)) (→ I64)
                      (let ((texture (integer-or (member-or holder name) "index" -1)))
                        (if (< texture 0) -1 (array-ref images texture)))))
             (strength (number-or (member-or (member-or material "extensions")
                                             "KHR_materials_emissive_strength")
                                  "emissiveStrength"
                                  1.0)))
        (new Material
          (base-color (numbers-or pbr "baseColorFactor" (list 1.0 1.0 1.0 1.0)))
          (base-texture (image pbr "baseColorTexture"))
          (metallic (number-or pbr "metallicFactor" 1.0))
          (roughness (number-or pbr "roughnessFactor" 1.0))
          (metal-rough-texture (image pbr "metallicRoughnessTexture"))
          (normal-texture (image material "normalTexture"))
          (normal-scale (number-or (member-or material "normalTexture") "scale" 1.0))
          (emissive (map (lambda (channel) (* channel strength))
                         (numbers-or material "emissiveFactor" (list 0.0 0.0 0.0))))
          (emissive-texture (image material "emissiveTexture"))
          (alpha (let ((mode (text-or material "alphaMode" "OPAQUE")))
                   (cond ((string=? mode "MASK") 1)
                         ((string=? mode "BLEND") 2)
                         (else 0))))
          (alpha-cutoff (number-or material "alphaCutoff" 0.5))
          (double-sided (bool-or material "doubleSided" #f)))))

    ;; ---- Nodes ----

    ;; Each primitive under the default scene's roots, placed by the
    ;; matrices of the nodes above it.
    (define (scene-placed (json Json) (meshes (Array (List Primitive)))) (→ (List Placed))
      (let* ((scenes (items json "scenes"))
             (roots (if (null? scenes)
                        (Nil)
                        (items (list-ref scenes (integer-or json "scene" 0)) "nodes")))
             (nodes (list->array (items json "nodes"))))
        (concatenate
         (map (lambda (root) (node-placed nodes meshes (json-index root) identity)) roots))))

    (define (node-placed (nodes (Array Json))
                         (meshes (Array (List Primitive)))
                         (index I64)
                         (parent (List F64)))
      (→ (List Placed))
      (let* ((node (array-ref nodes index))
             (matrix (multiply parent (local-matrix node)))
             (own (match (json-member node "mesh")
                    ((Some (JsonInteger mesh))
                     (map (lambda (primitive) (new Placed (primitive primitive) (matrix matrix)))
                          (array-ref meshes mesh)))
                    (_ (Nil)))))
        (append own
                (concatenate
                 (map (lambda (child) (node-placed nodes meshes (json-index child) matrix))
                      (items node "children"))))))

    (define (accessor-bounds (accessor Json)) (→ (Pair (List F64) (List F64)))
      (new Pair
        (first (numbers-or accessor "min" (list 0.0 0.0 0.0)))
        (second (numbers-or accessor "max" (list 0.0 0.0 0.0)))))

    (define (json-index (value Json)) (→ I64)
      (match value
        ((JsonInteger index) index)
        (_ 0)))

    ;; A node's `matrix`, or its translation, rotation and scale composed.
    (define (local-matrix (node Json)) (→ (List F64))
      (match (json-member node "matrix")
        ((Some _) (numbers-or node "matrix" identity))
        ((None)
         (trs (numbers-or node "translation" (list 0.0 0.0 0.0))
              (numbers-or node "rotation" (list 0.0 0.0 0.0 1.0))
              (numbers-or node "scale" (list 1.0 1.0 1.0))))))

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

    ;; A GLB file's JSON and binary chunk, empty when it has none, or
    ;; nothing for bytes that are not GLB: a 12-byte header starting
    ;; "glTF", then chunks of a length, a type and that many bytes.
    (define (glb-chunks (bytes Bytes)) (→ (Option (Pair Bytes Bytes)))
      (if (and (>= (array-length bytes) 20) (= (word bytes 0) 1179937895))
          (let* ((json-end (+ 20 (word bytes 12)))
                 (bin (+ 8 json-end))
                 (bin-end (if (<= bin (array-length bytes)) (+ bin (word bytes json-end)) bin)))
            (Some (new Pair
                    (first (subarray bytes 20 json-end))
                    (second (subarray bytes
                                      (min bin (array-length bytes))
                                      (min bin-end (array-length bytes)))))))
          (None)))

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

    (define (items (json Json) (name String)) (→ (List Json))
      (match (json-member json name)
        ((Some (JsonArray values)) values)
        (_ (Nil))))

    (define (integer-or (json Json) (name String) (default I64)) (→ I64)
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

    (define (numbers-or (json Json) (name String) (default (List F64))) (→ (List F64))
      (match (json-member json name)
        ((Some (JsonArray values)) (map (lambda (value) (number-of value 0.0)) values))
        (_ default)))

    (define (text-or (json Json) (name String) (default String)) (→ String)
      (match (json-member json name)
        ((Some (JsonString value)) value)
        (_ default)))

    (define (bool-or (json Json) (name String) (default Bool)) (→ Bool)
      (match (json-member json name)
        ((Some (JsonBool value)) value)
        (_ default)))

    ))
