;; A bounding volume hierarchy over triangles, built on the device as a linear BVH (Karras, "Maximizing Parallelism in the
;; Construction of BVHs, Octrees, and k-d Trees", 2012):
;;
;;   morton          each triangle's centroid, in the scene's box, as a
;;                   30-bit Morton code; the keys are padded to a power of
;;                   two with the largest key, so they sort last
;;   sort_step       one compare-exchange step of a bitonic sort of the
;;                   keys with their triangles, `j` and `k` its distance
;;                   and block
;;   build_leaves    a leaf for each sorted triangle, with its box
;;   build_internal  each internal node's children, from where the sorted
;;                   keys' common prefix shortens
;;   refit           each internal node's box from its children's
;;   pack            each internal node as the tracer reads it: both
;;                   children's boxes, and each child an internal node's
;;                   index or, with its top bit set, a leaf's triangle
;;
;; There are n - 1 internal nodes, 0 the root, then n leaves; a single
;; triangle is a lone leaf at 0. A leaf's `right` is LEAF and its `left`
;; its triangle. The refit reads one node array and writes the other, so
;; no invocation reads another's writes within a dispatch: after as many
;; passes as the tree is deep, every box is right, and passes beyond
;; change nothing. `BvhBuild` comes from Pod: the triangles' box, then n,
;; the padded count, and the step's j and k, then where positions are: a
;; vertex's first word and the words between vertices.

(struct Node
        (low vec3f)
        (left u32)
        (high vec3f)
        (right u32))

(const LEAF 4294967295u)

((var uniform) (@group 0) (@binding 0) (build BvhBuild))

((var storage read_write) (@group 0) (@binding 1) (keys (array u32)))

((var storage read_write) (@group 0) (@binding 2) (triangles (array u32)))

((var storage read) (@group 0) (@binding 3) (positions (array f32)))

((var storage read) (@group 0) (@binding 4) (indices (array u32)))

((var storage read_write) (@group 0) (@binding 5) (nodes (array Node)))

((var storage read) (@group 0) (@binding 6) (source (array Node)))

;; Two children's boxes; a child is an index, or a triangle with TRIANGLE
;; set.
(struct Wide
        (left_low vec3f)
        (left u32)
        (left_high vec3f)
        (right u32)
        (right_low vec3f)
        (pad0 u32)
        (right_high vec3f)
        (pad1 u32))

(const TRIANGLE 2147483648u)

((var storage read_write) (@group 0) (@binding 7) (wide (array Wide)))

(fn item ((id vec3u)) (-> u32)
    (return (+ (get id x) (* (get id y) 16776960u))))

(fn count () (-> u32)
    (return (u32 (get build counts x))))

(fn corner ((triangle u32) (k u32)) (-> vec3f)
    (let at_word (+
                  (* (at indices (+ (* triangle 3u) k)) (u32 (get build words x)))
                  (u32 (get build words y))))
    (return
     (vec3f (at positions at_word) (at positions (+ at_word 1u)) (at positions (+ at_word 2u)))))

;; Ten bits spread to every third.
(fn spread ((value u32)) (-> u32)
    (var x (bit-and value 1023u))
    (= x (bit-and (bit-or x (<< x 16u)) 50331903u))
    (= x (bit-and (bit-or x (<< x 8u)) 50393103u))
    (= x (bit-and (bit-or x (<< x 4u)) 51130563u))
    (= x (bit-and (bit-or x (<< x 2u)) 153391689u))
    (return x))

(fn (@compute) (@workgroup_size 256) morton (((@builtin global_invocation_id) id vec3u))
    (let i (item id))
    (if ((>= i (u32 (get build counts y))) (return)))
    (if ((>= i (count)) (= (at keys i) LEAF) (= (at triangles i) LEAF) (return)))
    (let centroid (/ (+ (corner i 0u) (corner i 1u) (corner i 2u)) 3.0))
    (let extent (max (- (get build high xyz) (get build low xyz)) (vec3f 1e-12)))
    (let unit (clamp (/ (- centroid (get build low xyz)) extent) (vec3f 0.0) (vec3f 1.0)))
    (let cell (min (vec3u (* unit 1024.0)) (vec3u 1023u)))
    (= (at keys i)
       (bit-or (<< (spread (get cell x)) 2u)
               (bit-or (<< (spread (get cell y)) 1u) (spread (get cell z)))))
    (= (at triangles i) i))

;; Invocation i compares the pair at distance j that it names, ascending
;; within blocks of k whose bit is clear.
(fn (@compute) (@workgroup_size 256) sort_step (((@builtin global_invocation_id) id vec3u))
    (let i (item id))
    (let j (u32 (get build counts z)))
    (let k (u32 (get build counts w)))
    (if ((>= (* i 2u) (u32 (get build counts y))) (return)))
    (let a (+ (* (* 2u j) (/ i j)) (- i (* j (/ i j)))))
    (let b (+ a j))
    (let ascending (== (bit-and a k) 0u))
    (let ka (at keys a))
    (let kb (at keys b))
    (if ((== (> ka kb) ascending)
         (= (at keys a) kb)
         (= (at keys b) ka)
         (let ta (at triangles a))
         (= (at triangles a) (at triangles b))
         (= (at triangles b) ta))))

(fn (@compute) (@workgroup_size 256) build_leaves (((@builtin global_invocation_id) id vec3u))
    (let i (item id))
    (if ((>= i (count)) (return)))
    (let triangle (at triangles i))
    (let a (corner triangle 0u))
    (let b (corner triangle 1u))
    (let c (corner triangle 2u))
    (= (at nodes (+ (- (count) 1u) i)) (Node (min a (min b c)) triangle (max a (max b c)) LEAF)))

;; The length of the common prefix of keys i and j, the index breaking
;; ties, or -1 when j is past either end.
(fn delta ((i i32) (j i32)) (-> i32)
    (if ((or (< j 0) (>= j (i32 (count)))) (return -1)))
    (let ki (at keys i))
    (let kj (at keys j))
    (if ((== ki kj) (return (+ 32 (i32 (countLeadingZeros (bit-xor (u32 i) (u32 j))))))))
    (return (i32 (countLeadingZeros (bit-xor ki kj)))))

(fn child ((index i32) (leaf bool)) (-> u32)
    (return (select (u32 index) (+ (- (count) 1u) (u32 index)) leaf)))

(fn (@compute) (@workgroup_size 256) build_internal (((@builtin global_invocation_id) id vec3u))
    (let u (item id))
    (if ((>= (+ u 1u) (count)) (return)))
    (let i (i32 u))
    (let d (select -1 1 (> (delta i (+ i 1)) (delta i (- i 1)))))
    (let lower (delta i (- i d)))
    (var reach 2)
    (while (> (delta i (+ i (* reach d))) lower) (*= reach 2))
    (var l 0)
    (var t (/ reach 2))
    (while (>= t 1)
           (if ((> (delta i (+ i (* (+ l t) d))) lower) (+= l t)))
           (/= t 2))
    (let j (+ i (* l d)))
    (let prefix (delta i j))
    (var s 0)
    (var stride l)
    (loop
     (= stride (/ (+ stride 1) 2))
     (if ((> (delta i (+ i (* (+ s stride) d))) prefix) (+= s stride)))
     (if ((<= stride 1) (break))))
    (let split (+ i (* s d) (min d 0)))
    (let left (child split (== (min i j) split)))
    (let right (child (+ split 1) (== (max i j) (+ split 1))))
    (= (get (at nodes u) left) left)
    (= (get (at nodes u) right) right))

(fn (@compute) (@workgroup_size 256) refit (((@builtin global_invocation_id) id vec3u))
    (let u (item id))
    (if ((>= u (- (* 2u (count)) 1u)) (return)))
    (let node (at source u))
    (if ((== (get node right) LEAF) (= (at nodes u) node) (return)))
    (let a (at source (get node left)))
    (let b (at source (get node right)))
    (= (at nodes u)
       (Node (min (get a low) (get b low))
             (get node left)
             (max (get a high) (get b high))
             (get node right))))

(fn pointer ((index u32)) (-> u32)
    (let node (at source index))
    (return (select index (bit-or TRIANGLE (get node left)) (== (get node right) LEAF))))

;; A lone triangle is a root with the leaf on both sides.
(fn (@compute) (@workgroup_size 256) pack (((@builtin global_invocation_id) id vec3u))
    (let u (item id))
    (if ((>= u (max (- (count) 1u) 1u)) (return)))
    (var left 0u)
    (var right 0u)
    (if ((> (count) 1u) (= left (get (at source u) left)) (= right (get (at source u) right))))
    (let a (at source left))
    (let b (at source right))
    (= (at wide u)
       (Wide (get a low)
             (pointer left)
             (get a high)
             (pointer right)
             (get b low)
             0u
             (get b high)
             0u)))
