;; One pass of a least-significant-digit radix sort, four bits of the key
;; at `sorting.shift`, over blocks of 256 keys, an invocation a key. It
;; sorts the first `counted[0]` keys, at most `sorting.capacity`, and the
;; blocks they fill, which a pass's workgroups take in turn, each the next
;; block after the ones all the workgroups took, so a pass costs the keys
;; counted, not the capacity. `count_digits` counts each block's keys by
;; digit into `counts`, digit-major: the count of digit d in block b is at
;; d * blocks + b. Scanned exclusively, that table holds where each
;; block's keys of each digit start in the output, every smaller digit's
;; keys first and then this digit's in earlier blocks; past the blocks
;; counted the table holds what an earlier sort left, which no prefix
;; before it reads. `scatter` writes each key and its value there, after
;; the keys of its digit earlier in its block, so a pass is stable and the
;; passes together sort. `SortPass` comes from Pod.
((var uniform) (@group 0) (@binding 0) (sorting SortPass))

((var storage read) (@group 0) (@binding 1) (keys_in (array u32)))

((var storage read) (@group 0) (@binding 2) (values_in (array u32)))

((var storage read_write) (@group 0) (@binding 3) (counts (array u32)))

((var storage read_write) (@group 0) (@binding 4) (keys_out (array u32)))

((var storage read_write) (@group 0) (@binding 5) (values_out (array u32)))

((var storage read) (@group 0) (@binding 6) (counted (array u32)))

((var workgroup) (bins (array (atomic u32) 16)))

((var workgroup) (digits (array u32 256)))

(fn digit ((key u32)) (-> u32)
    (return (bit-and (>> key (u32 (get sorting shift))) 15u)))

;; The keys the sort sorts, and the blocks of 256 they fill.
(fn key_count () (-> u32)
    (return (min (at counted 0) (u32 (get sorting capacity)))))

(fn block_count () (-> u32)
    (return (/ (+ (key_count) 255u) 256u)))

(fn (@compute)
    (@workgroup_size 256)
    count_digits
    (((@builtin local_invocation_id) local vec3u)
     ((@builtin workgroup_id) group vec3u)
     ((@builtin num_workgroups) groups vec3u))
    (let t (get local x))
    (let blocks (block_count))
    (for ((var block (get group x)) (< block blocks) (+= block (get groups x)))
         (let i (+ (* block 256u) t))
         (if ((< t 16u) (atomicStore (address-of (at bins t)) 0u)))
         (workgroupBarrier)
         (if ((< i (key_count)) (atomicAdd (address-of (at bins (digit (at keys_in i)))) 1u)))
         (workgroupBarrier)
         (if ((< t 16u)
              (= (at counts (+ (* t blocks) block)) (atomicLoad (address-of (at bins t))))))))

;; A key's rank among its block's keys of the same digit is how many come
;; before it: a count over at most 255 neighbours in workgroup memory, the
;; simplest stable ranking. Keys past the count take digit 16, which no
;; key has. A block's digits are read before the next block's are written.
(fn (@compute)
    (@workgroup_size 256)
    scatter
    (((@builtin local_invocation_id) local vec3u)
     ((@builtin workgroup_id) group vec3u)
     ((@builtin num_workgroups) groups vec3u))
    (let t (get local x))
    (let blocks (block_count))
    (for ((var block (get group x)) (< block blocks) (+= block (get groups x)))
         (let i (+ (* block 256u) t))
         (let inside (< i (key_count)))
         (var d 16u)
         (if (inside (= d (digit (at keys_in i)))))
         (= (at digits t) d)
         (workgroupBarrier)
         (if (inside
              (var rank 0u)
              (for ((var j 0u) (< j t) (+= j 1u)) (if ((== (at digits j) d) (+= rank 1u))))
              (let to (+ (at counts (+ (* d blocks) block)) rank))
              (= (at keys_out to) (at keys_in i))
              (= (at values_out to) (at values_in i))))
         (workgroupBarrier)))
