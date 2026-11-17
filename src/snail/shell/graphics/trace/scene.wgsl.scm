;; The scene as kernels read it, in group 1: its vertices and triangles
;; (trace/scene.sld unpacks them), its materials and its texture layers;
;; with random numbers, and `cutout`, the test the ray queries of
;; (snail shell graphics bvh) call as a ray crosses a triangle. Both the
;; queries and the path kernels include this text. `SurfaceMaterial`
;; comes from Pod.
(struct Vertex
        (position vec3f)
        (u f32)
        (normal vec3f)
        (v f32)
        (tangent vec4f)
        (material u32)
        (pad0 u32)
        (pad1 u32)
        (pad2 u32))

((var storage read) (@group 1) (@binding 0) (vertices (array Vertex)))

((var storage read) (@group 1) (@binding 1) (indices (array u32)))

((var storage read) (@group 1) (@binding 2) (materials (array SurfaceMaterial)))

(var (@group 1) (@binding 3) (layers (texture_2d_array f32)))

(var (@group 1) (@binding 4) (repeat sampler))

;; ---- Random numbers ----

(fn pcg ((value u32)) (-> u32)
    (let state (+ (* value 747796405u) 2891336453u))
    (let word (* (bit-xor (>> state (+ (>> state 28u) 4u)) state) 277803737u))
    (return (bit-xor (>> word 22u) word)))

(fn random ((seed (ptr function u32))) (-> f32)
    (= (deref seed) (pcg (deref seed)))
    (return (* (f32 (>> (deref seed) 8u)) (/ 1.0 16777216.0))))

;; ---- Triangles ----

;; A triangle's corner.
(fn corner ((triangle u32) (k u32)) (-> Vertex)
    (return (at vertices (at indices (+ (* triangle 3u) k)))))

(fn uv_of ((v Vertex)) (-> vec2f)
    (return (vec2f (get v u) (get v v))))

(fn decoded ((c vec3f)) (-> vec3f)
    (return (select (pow (/ (+ c 0.055) 1.055) (vec3f 2.4)) (/ c 12.92) (<= c (vec3f 0.04045)))))

(fn texel ((layer i32) (uv vec2f) (level f32)) (-> vec4f)
    (if ((< layer 0) (return (vec4f 1.0))))
    (return (textureSampleLevel layers repeat uv layer level)))

;; Whether a cutout lets the ray through where it crosses `triangle`: a
;; masked material below its cutoff, or a blended one, by its alpha's
;; odds.
(fn cutout ((triangle u32) (b vec2f) (seed (ptr function u32))) (-> bool)
    (let a (corner triangle 0u))
    (let m (at materials (get a material)))
    (let mode (get m factors w))
    (if ((== mode 0.0) (return false)))
    (let bb (corner triangle 1u))
    (let c (corner triangle 2u))
    (let uv (+ (* (uv_of a) (- 1.0 (get b x) (get b y))) (* (uv_of bb) (get b x)) (* (uv_of c) (get b y))))
    (let alpha (* (get m base_color w) (get (texel (get m textures x) uv 2.0) w)))
    (if ((== mode 1.0) (return (< alpha (get m emissive w)))))
    (return (< alpha (random seed))))
