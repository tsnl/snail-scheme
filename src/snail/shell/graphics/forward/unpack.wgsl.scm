;; A glTF scene's accessors unpacked on the device into one vertex array
;; and one index array (gltf.sld, scene.sld). `data` is every buffer laid
;; end to end as words; each `Unpack` names one placed primitive's
;; accessors by byte offset, stride, component type and whether integers
;; are normalized, an offset of -1 for one it lacks. Vertices come out in
;; the world, under the primitive's matrix, and indices count from the
;; first vertex of all, so the whole scene is one indexed draw and one
;; set of triangles to trace. A missing normal or tangent comes out zero,
;; and its user derives one from the triangle.
;;
;; Each invocation finds its primitive by binary search over the
;; primitives' first vertex or first triangle, so a scene is two
;; dispatches however many primitives it has.
(struct Vertex
        (position vec3f)
        (u f32)
        (normal vec3f)
        (v f32)
        (tangent vec4f))

((var storage read) (@group 0) (@binding 0) (data (array u32)))

((var storage read) (@group 0) (@binding 1) (unpacks (array Unpack)))

((var storage read_write) (@group 0) (@binding 2) (vertices (array Vertex)))

((var storage read_write) (@group 0) (@binding 3) (indices (array u32)))

;; The primitive whose range of `first` holds `item`: the last whose first
;; is at most it.
(fn primitive_of ((item u32) (by_triangle bool)) (-> u32)
    (var low 0u)
    (var high (- (arrayLength (address-of unpacks)) 1u))
    (while (< low high)
           (let middle (/ (+ low high 1u) 2u))
           (let first (select (u32 (get (at unpacks middle) first_vertex))
                              (/ (u32 (get (at unpacks middle) first_index)) 3u)
                              by_triangle))
           (if ((<= first item) (= low middle))
               (else (= high (- middle 1u)))))
    (return low))

(fn word ((byte u32)) (-> u32)
    (return (at data (/ byte 4u))))

(fn component_size ((format i32)) (-> u32)
    (return (select (select 4u 2u (or (== format 5122) (== format 5123)))
                    1u
                    (or (== format 5120) (== format 5121)))))
;; glTF signed and unsigned integer accessors can be normalized. The
;; minimum signed value maps to -1, just like the vertex fetch hardware.
(fn component_at ((byte u32) (component i32) (normalized i32)) (-> f32)
    (let value (word byte))
    (if ((== component 5126) (return ((bitcast f32) value))))
    (let size (component_size component))
    (if ((== size 4u) (return (f32 value))))
    (let bits (* size 8u)) (let shift (* (bit-and byte 3u) 8u))
    (let unsigned (extractBits value shift bits))
    (if ((or (== component 5120) (== component 5122))
         (let v (f32 (extractBits ((bitcast i32) value) shift bits)))
         (let hi (select 32767.0 127.0 (== size 1u)))
         (return (select v (max -1.0 (/ v hi)) (!= normalized 0)))))
    (let hi (select 65535.0 255.0 (== size 1u)))
    (return (select (f32 unsigned) (/ (f32 unsigned) hi) (!= normalized 0))))

(fn element ((accessor vec4i) (index u32) (part u32)) (-> f32)
    (let size (component_size (get accessor z)))
    (return (component_at (+ (u32 (get accessor x)) (* index (u32 (get accessor y))) (* part size))
                          (get accessor z)
                          (get accessor w))))

(fn index_at ((accessor vec4i) (index u32)) (-> u32)
    (let byte (+ (u32 (get accessor x)) (* index (u32 (get accessor y)))))
    (let shift (* (bit-and byte 3u) 8u))
    (if ((== (get accessor z) 5121) (return (bit-and (>> (word byte) shift) 255u)))
        ((== (get accessor z) 5123) (return (bit-and (>> (word byte) shift) 65535u))))
    (return (word byte)))

(fn element3 ((accessor vec4i) (index u32)) (-> vec3f)
    (return
     (vec3f (element accessor index 0u) (element accessor index 1u) (element accessor index 2u))))

(fn (@compute) (@workgroup_size 256) unpack_vertices (((@builtin global_invocation_id) id vec3u))
    (let item (+ (get id x) (* (get id y) 16776960u)))
    (if ((>= item (arrayLength (address-of vertices))) (return)))
    (let p (at unpacks (primitive_of item false)))
    (let index (- item (u32 (get p first_vertex))))
    (var (out Vertex))
    (= (get out position)
       (get (* (get p matrix) (vec4f (element3 (get p positions) index) 1.0)) xyz))
    (if ((>= (get p normals x) 0)
         (= (get out normal)
            (normalize
             (get (* (get p normal_matrix) (vec4f (element3 (get p normals) index) 0.0)) xyz)))))
    (if ((>= (get p uvs x) 0)
         (= (get out u) (element (get p uvs) index 0u))
         (= (get out v) (element (get p uvs) index 1u))))
    (if ((>= (get p tangents x) 0)
         (let t (* (get p matrix) (vec4f (element3 (get p tangents) index) 0.0)))
         (= (get out tangent) (vec4f (normalize (get t xyz)) (element (get p tangents) index 3u)))))
    (= (at vertices item) out))

(fn (@compute) (@workgroup_size 256) unpack_triangles (((@builtin global_invocation_id) id vec3u))
    (let triangle (+ (get id x) (* (get id y) 16776960u)))
    (if ((>= (* triangle 3u) (arrayLength (address-of indices))) (return)))
    (let p (at unpacks (primitive_of triangle true)))
    (let local (- (* triangle 3u) (u32 (get p first_index))))
    (for ((var corner 0u) (< corner 3u) (+= corner 1u))
         (var index (+ local corner))
         (if ((>= (get p indices x) 0) (= index (index_at (get p indices) index))))
         (= (at indices (+ (* triangle 3u) corner)) (+ index (u32 (get p first_vertex))))))


;; The suffix of moving vertices uses a mesh-local immutable source. delta
;; is in world space and leads from this frame back to the previous one.
(struct VertexInfluence (joints vec4i) (weights vec4f))
((var storage read) (@group 0) (@binding 4) (rest_vertices (array Vertex)))
((var storage read) (@group 0) (@binding 5) (influences (array VertexInfluence)))
((var storage read) (@group 0) (@binding 6) (palette (array mat4x4f)))

(fn (@compute) (@workgroup_size 256) pose_vertices (((@builtin global_invocation_id) id vec3u))
    (let i (+ (get id x) (* (get id y) 16776960u)))
    (let count (arrayLength (address-of influences)))
    (if ((>= i count) (return)))
    (let at_vertex (+ (- (arrayLength (address-of vertices)) count) i))
    (let skin (at influences i))
    (let j (get skin joints))
    (let w (get skin weights))
    (let m (+ (* (at palette (get j x)) (get w x)) (* (at palette (get j y)) (get w y))
              (* (at palette (get j z)) (get w z)) (* (at palette (get j w)) (get w w))))
    (let a (get (at m 0) xyz))
    (let b (get (at m 1) xyz))
    (let c (get (at m 2) xyz))
    ;; The cofactor matrix times the determinant sign transforms a normal
    ;; even with nonuniform scale. A collapsed normal falls back to the face.
    (let flip (select 1.0 -1.0 (< (dot a (cross b c)) 0.0)))
    (var v (at rest_vertices at_vertex))
    (let n (* (mat3x3f (cross b c) (cross c a) (cross a b)) (get v normal)))
    (= (get v normal) (* n (/ flip (max (length n) 1e-12))))
    (= (get v tangent) (vec4f (* (mat3x3f a b c) (get v tangent xyz)) (* flip (get v tangent w))))
    (= (get v position) (get (* m (vec4f (get v position) 1.0)) xyz))
    (= (at vertices at_vertex) v))
