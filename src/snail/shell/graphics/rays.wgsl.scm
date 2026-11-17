;; Ray queries against a BVH (bvh.wgsl.scm), a queue of rays at a time,
;; since WebGPU has no ray tracing of its own:
;;
;;   intersect  each ray's nearest hit before its limit
;;   occlude    whether anything lies before each ray's limit, the walk
;;              stopping at the first hit it finds
;;
;; Each writes the ray's `hit`: t, the triangle (BVH_NONE for no hit),
;; and the barycentrics of corners 1 and 2. The queue holds
;; `ray_count` rays; a dispatch covers the queue's capacity in rows of
;; 65535 workgroups of 64, and invocations past the count return.
;;
;; The program that includes this text defines, in group 1 with whatever
;; it needs, `cutout`: whether a ray goes through `triangle` where it
;; crosses it, so cutouts and translucent surfaces let rays by. `seed`
;; is the ray's, for a stochastic cutout.
;;
;;   fn cutout(triangle: u32, barycentric: vec2f, seed: ptr<function, u32>) -> bool
;;
;; `BvhLayout` comes from Pod: a vertex's position as words, the stride
;; and the first word's offset.
(struct BvhNode
        (left_low vec3f)
        (left u32)
        (left_high vec3f)
        (right u32)
        (right_low vec3f)
        (pad0 u32)
        (right_high vec3f)
        (pad1 u32))

;; A ray: origin and limit, direction and seed, the hit the query writes,
;; and two vectors the queries never read, for the program's own state.
(struct RayHit
        (t f32)
        (triangle u32)
        (barycentric vec2f))

(struct Ray
        (origin vec4f)
        (direction vec4f)
        (hit RayHit)
        (payload vec4f)
        (more vec4f))

(const BVH_TRIANGLE 2147483648u)

(const BVH_NONE 4294967295u)

((var storage read) (@group 0) (@binding 0) (bvh_nodes (array BvhNode)))

((var storage read) (@group 0) (@binding 1) (bvh_positions (array f32)))

((var storage read) (@group 0) (@binding 2) (bvh_indices (array u32)))

((var uniform) (@group 0) (@binding 3) (bvh_layout BvhLayout))

((var storage read_write) (@group 0) (@binding 4) (rays (array Ray)))

((var storage read) (@group 0) (@binding 5) (ray_count u32))

;; ---- Triangles ----

(fn bvh_corner ((triangle u32) (k u32)) (-> vec3f)
    (let at_word (+ (* (at bvh_indices (+ (* triangle 3u) k)) (u32 (get bvh_layout shape x))) (u32 (get bvh_layout shape y))))
    (return (vec3f (at bvh_positions at_word) (at bvh_positions (+ at_word 1u)) (at bvh_positions (+ at_word 2u)))))

;; Where the ray first meets the triangle (Möller and Trumbore), as t and
;; barycentrics, or t of -1.
(fn bvh_crossing ((triangle u32) (origin vec3f) (direction vec3f)) (-> vec3f)
    (let a (bvh_corner triangle 0u))
    (let e1 (- (bvh_corner triangle 1u) a))
    (let e2 (- (bvh_corner triangle 2u) a))
    (let p (cross direction e2))
    (let det (dot e1 p))
    (if ((< (abs det) 1e-14) (return (vec3f -1.0))))
    (let inverse (/ 1.0 det))
    (let s (- origin a))
    (let u (* (dot s p) inverse))
    (let q (cross s e1))
    (let v (* (dot direction q) inverse))
    (if ((or (< u 0.0) (< v 0.0) (> (+ u v) 1.0)) (return (vec3f -1.0))))
    (return (vec3f (* (dot e2 q) inverse) u v)))

;; ---- Traversal ----

;; Where the ray enters the box from low to high, or -1 when it misses
;; or enters past `limit`; a NaN misses, since every comparison with it
;; fails. (A miss cannot be `limit` plus one: at 1e30 that is 1e30.)
(fn bvh_entering ((low vec3f) (high vec3f) (origin vec3f) (inverse vec3f) (limit f32)) (-> f32)
    (let t0 (* (- low origin) inverse))
    (let t1 (* (- high origin) inverse))
    (let near (max (max (min (get t0 x) (get t1 x)) (min (get t0 y) (get t1 y))) (min (get t0 z) (get t1 z))))
    (let far (min (min (max (get t0 x) (get t1 x)) (max (get t0 y) (get t1 y))) (max (get t0 z) (get t1 z))))
    (if ((not (and (<= near far) (>= far 0.0) (<= near limit))) (return -1.0)))
    (return (max near 0.0)))

;; The hit with the triangle, when it is nearer than the one so far and
;; its cutout does not let the ray through.
(fn bvh_tested ((hit (ptr function RayHit)) (triangle u32) (origin vec3f) (direction vec3f) (seed (ptr function u32)))
    (-> bool)
    (let found (bvh_crossing triangle origin direction))
    (if ((and (> (get found x) 0.0) (< (get found x) (get (deref hit) t)) (not (cutout triangle (get found yz) seed)))
         (= (deref hit) (RayHit (get found x) triangle (get found yz)))
         (return true)))
    (return false))

;; The nearest hit before `limit`, or, for occlusion, the first found.
;; Each node holds both children's boxes, so a step tests both: a leaf
;; child's triangle is tested at once, and of two internal children the
;; walk goes on into the nearer and keeps the farther. A walk gives up
;; after 8192 steps, far more than a ray through Sponza needs, so no ray
;; can hold up the device long enough to lose it.
(fn bvh_traced ((origin vec3f) (direction vec3f) (limit f32) (occlusion bool) (seed (ptr function u32))) (-> RayHit)
    (var hit (RayHit limit BVH_NONE (vec2f 0.0)))
    (let inverse (/ (vec3f 1.0) (select direction (vec3f 1e-30) (== direction (vec3f 0.0)))))
    (var (stack (array u32 64)))
    (var top 0)
    (var node 0u)
    (for ((var steps 0) (< steps 8192) (+= steps 1))
      (let w (at bvh_nodes node))
      (let tl (bvh_entering (get w left_low) (get w left_high) origin inverse (get hit t)))
      (var go_left (>= tl 0.0))
      (if ((and go_left (!= (bit-and (get w left) BVH_TRIANGLE) 0u))
           (= go_left false)
           (if ((and (bvh_tested (address-of hit) (bit-xor (get w left) BVH_TRIANGLE) origin direction seed) occlusion)
                (return hit)))))
      (let tr (bvh_entering (get w right_low) (get w right_high) origin inverse (get hit t)))
      (var go_right (>= tr 0.0))
      (if ((and go_right (!= (bit-and (get w right) BVH_TRIANGLE) 0u))
           (= go_right false)
           (if ((and (bvh_tested (address-of hit) (bit-xor (get w right) BVH_TRIANGLE) origin direction seed) occlusion)
                (return hit)))))
      (= go_left (and go_left (<= tl (get hit t))))
      (= go_right (and go_right (<= tr (get hit t))))
      (if ((and go_left go_right)
           (let near_left (<= tl tr))
           (if ((< top 64) (= (at stack top) (select (get w left) (get w right) near_left)) (+= top 1)))
           (= node (select (get w right) (get w left) near_left)))
          (go_left (= node (get w left)))
          (go_right (= node (get w right)))
          ((== top 0) (break))
          (else (-= top 1) (= node (at stack top)))))
    (return hit))

;; ---- Queries ----

;; Rows hold 65535 workgroups of 64, every row but the last full.
(fn ray_item ((id vec3u)) (-> u32)
    (return (+ (get id x) (* (get id y) 4194240u))))

(fn queried ((i u32) (occlusion bool))
    (let ray (at rays i))
    (var seed ((bitcast u32) (get ray direction w)))
    (= (get (at rays i) hit) (bvh_traced (get ray origin xyz) (get ray direction xyz) (get ray origin w) occlusion (address-of seed))))

(fn (@compute) (@workgroup_size 64) intersect (((@builtin global_invocation_id) id vec3u))
    (let i (ray_item id))
    (if ((< i ray_count) (queried i false))))

(fn (@compute) (@workgroup_size 64) occlude (((@builtin global_invocation_id) id vec3u))
    (let i (ray_item id))
    (if ((< i ray_count) (queried i true))))
