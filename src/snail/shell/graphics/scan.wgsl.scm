;; Blelloch's exclusive scan of a tile of 512 numbers in workgroup memory,
;; one workgroup of 256 invocations a tile, two numbers each. The upsweep
;; builds a tree of partial sums in place, its root the tile's total, which
;; goes to `sums` at the tile's index; the root is then cleared and the
;; downsweep passes each node's sum to the right and the sum left of it to
;; the left, leaving each number as the sum of those before it in the
;; tile. `add_sums` then adds each tile's scanned total to its numbers.
;; Numbers past the level's count read as 0 and are not written.
;; `ScanLevel` comes from Pod.
((var uniform) (@group 0) (@binding 0) (level ScanLevel))

((var storage read_write) (@group 0) (@binding 1) (data (array u32)))

((var storage read_write) (@group 0) (@binding 2) (sums (array u32)))

((var workgroup) (scratch (array u32 512)))

(fn load ((index u32)) (-> u32)
    (if ((< index (u32 (get level count))) (return (at data index))))
    (return 0u))

(fn store ((index u32) (value u32))
    (if ((< index (u32 (get level count))) (= (at data index) value))))

;; The left and right children of node `t` at a level whose nodes are
;; `offset` apart.
(fn left_child ((t u32) (offset u32)) (-> u32)
    (return (- (* offset (+ (* 2u t) 1u)) 1u)))

(fn right_child ((t u32) (offset u32)) (-> u32)
    (return (- (* offset (+ (* 2u t) 2u)) 1u)))

(fn (@compute)
    (@workgroup_size 256)
    scan_tiles
    (((@builtin local_invocation_id) local vec3u) ((@builtin workgroup_id) group vec3u))
    (let t (get local x))
    (let base (* (get group x) 512u))
    (= (at scratch (* 2u t)) (load (+ base (* 2u t))))
    (= (at scratch (+ (* 2u t) 1u)) (load (+ base (* 2u t) 1u)))
    (var offset 1u)
    (for ((var d 256u) (> d 0u) (= d (>> d 1u)))
         (workgroupBarrier)
         (if ((< t d) (+= (at scratch (right_child t offset)) (at scratch (left_child t offset)))))
         (*= offset 2u))
    (workgroupBarrier)
    (if ((== t 0u) (= (at sums (get group x)) (at scratch 511u)) (= (at scratch 511u) 0u)))
    (for ((var d 1u) (< d 512u) (*= d 2u))
         (= offset (>> offset 1u))
         (workgroupBarrier)
         (if ((< t d)
              (let before (at scratch (left_child t offset)))
              (= (at scratch (left_child t offset)) (at scratch (right_child t offset)))
              (+= (at scratch (right_child t offset)) before))))
    (workgroupBarrier)
    (store (+ base (* 2u t)) (at scratch (* 2u t)))
    (store (+ base (* 2u t) 1u) (at scratch (+ (* 2u t) 1u))))

(fn (@compute)
    (@workgroup_size 256)
    add_sums
    (((@builtin local_invocation_id) local vec3u) ((@builtin workgroup_id) group vec3u))
    (let base (+ (* (get group x) 512u) (* 2u (get local x))))
    (let total (at sums (get group x)))
    (store base (+ (load base) total))
    (store (+ base 1u) (+ (load (+ base 1u)) total)))
