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
;; The walk starts at slot 0, the top level's root, and reads every node
;; as two slots, each a child's box with a pointer and a count: a count of
;; 0 points at the child's own two slots, a count above 0 at its leaf's
;; triangles, each a corner and two edges laid out in the leaves' order.
;;
;; The program that includes this text defines, in group 1 with whatever
;; it needs, `cutout`: whether a ray goes through `triangle` where it
;; crosses it, so cutouts and translucent surfaces let rays by. `seed`
;; is the ray's, for a stochastic cutout.
;;
;;   fn cutout(triangle: u32, barycentric: vec2f, seed: ptr<function, u32>) -> bool
(struct BvhSlot
        (low vec3f)
        (pointer u32)
        (high vec3f)
        (count u32))

(struct BvhTriangle
        (a vec3f)
        (id u32)
        (e1 vec3f)
        (pad u32)
        (e2 vec3f)
        (slot u32))

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

(const BVH_NONE 4294967295u)

((var storage read) (@group 0) (@binding 0) (bvh_slots (array BvhSlot)))

((var storage read) (@group 0) (@binding 1) (bvh_triangles (array BvhTriangle)))

((var storage read_write) (@group 0) (@binding 4) (rays (array Ray)))

((var storage read) (@group 0) (@binding 5) (ray_count u32))

;; ---- Triangles ----

;; Where the ray first meets the triangle (Möller and Trumbore), as t and
;; barycentrics, or t of -1.
(fn bvh_crossing ((tri BvhTriangle) (origin vec3f) (direction vec3f)) (-> vec3f)
    (let e1 (get tri e1))
    (let e2 (get tri e2))
    (let p (cross direction e2))
    (let det (dot e1 p))
    (if ((< (abs det) 1e-14) (return (vec3f -1.0))))
    (let inverse (/ 1.0 det))
    (let s (- origin (get tri a)))
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
    (let near (max
               (max (min (get t0 x) (get t1 x)) (min (get t0 y) (get t1 y)))
               (min (get t0 z) (get t1 z))))
    (let far (min
              (min (max (get t0 x) (get t1 x)) (max (get t0 y) (get t1 y)))
              (max (get t0 z) (get t1 z))))
    (if ((not (and (<= near far) (>= far 0.0) (<= near limit))) (return -1.0)))
    (return (max near 0.0)))

;; The leaf's triangles tested in turn, each hit nearer than the one so
;; far and not let through by its cutout kept; for occlusion, whether one
;; was found.
(fn bvh_leaf
    ((hit (ptr function RayHit))
     (leaf BvhSlot)
     (origin vec3f)
     (direction vec3f)
     (occlusion bool)
     (seed (ptr function u32)))
    (-> bool)
    (for ((var k 0u) (< k (get leaf count)) (+= k 1u))
         (let tri (at bvh_triangles (+ (get leaf pointer) k)))
         (let found (bvh_crossing tri origin direction))
         (if ((and (> (get found x) 0.0)
                   (< (get found x) (get (deref hit) t))
                   (not (cutout (get tri id) (get found yz) seed)))
              (= (deref hit) (RayHit (get found x) (get tri id) (get found yz)))
              (if (occlusion (return true))))))
    (return false))

;; The nearest hit before `limit`, or, for occlusion, the first found.
;; Each node is two slots, so a step tests both children: a leaf child's
;; triangles are tested at once, and of two internal children the walk
;; goes on into the nearer and keeps the farther. A walk gives up after
;; 8192 steps, far more than a ray through Sponza needs, so no ray can
;; hold up the device long enough to lose it.
(fn bvh_traced
    ((origin vec3f) (direction vec3f) (limit f32) (occlusion bool) (seed (ptr function u32)))
    (-> RayHit)
    (var hit (RayHit limit BVH_NONE (vec2f 0.0)))
    (let inverse (/ (vec3f 1.0) (select direction (vec3f 1e-30) (== direction (vec3f 0.0)))))
    (let root (at bvh_slots 0))
    (if ((< (bvh_entering (get root low) (get root high) origin inverse limit) 0.0) (return hit)))
    (if ((> (get root count) 0u)
         (bvh_leaf (address-of hit) root origin direction occlusion seed)
         (return hit)))
    (var (stack (array u32 64)))
    (var top 0)
    (var node (get root pointer))
    (for ((var steps 0) (< steps 8192) (+= steps 1))
         (let left (at bvh_slots node))
         (let right (at bvh_slots (+ node 1u)))
         (let tl (bvh_entering (get left low) (get left high) origin inverse (get hit t)))
         (var go_left (>= tl 0.0))
         (if ((and go_left (> (get left count) 0u))
              (= go_left false)
              (if ((and (bvh_leaf (address-of hit) left origin direction occlusion seed) occlusion)
                   (return hit)))))
         (let tr (bvh_entering (get right low) (get right high) origin inverse (get hit t)))
         (var go_right (>= tr 0.0))
         (if ((and go_right (> (get right count) 0u))
              (= go_right false)
              (if ((and (bvh_leaf (address-of hit) right origin direction occlusion seed) occlusion)
                   (return hit)))))
         (= go_left (and go_left (<= tl (get hit t))))
         (= go_right (and go_right (<= tr (get hit t))))
         (if ((and go_left go_right)
              (let near_left (<= tl tr))
              (if ((< top 64)
                   (= (at stack top) (select (get left pointer) (get right pointer) near_left))
                   (+= top 1)))
              (= node (select (get right pointer) (get left pointer) near_left)))
             (go_left (= node (get left pointer)))
             (go_right (= node (get right pointer)))
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
    (= (get (at rays i) hit)
       (bvh_traced (get ray origin xyz)
                   (get ray direction xyz)
                   (get ray origin w)
                   occlusion
                   (address-of seed))))

(fn (@compute) (@workgroup_size 64) intersect (((@builtin global_invocation_id) id vec3u))
    (let i (ray_item id))
    (if ((< i ray_count) (queried i false))))

(fn (@compute) (@workgroup_size 64) occlude (((@builtin global_invocation_id) id vec3u))
    (let i (ray_item id))
    (if ((< i ray_count) (queried i true))))
