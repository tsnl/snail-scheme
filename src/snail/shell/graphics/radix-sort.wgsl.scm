;; One pass of a least-significant-digit radix sort, eight bits of the key
;; at `sorting.shift`, over blocks of 256 keys, an invocation a key. It
;; sorts the first `counted[0]` keys, at most `sorting.capacity`, and the
;; blocks they fill, which the pass's workgroups share out in runs, the
;; first workgroup taking the first run, so a pass costs the keys counted,
;; not the capacity. `count_digits` counts each run's keys by digit into
;; `counts`, digit-major: the count of digit d in workgroup w's run is at
;; d * workgroups + w. Every workgroup writes all 256 of its counts, so
;; the table is whole after each count. Scanned exclusively, it holds
;; where each run's keys of each digit start in the output: every smaller
;; digit's keys first, then this digit's in earlier runs. `scatter` takes
;; its run's blocks in order and writes each key and its value there,
;; after the keys of its digit earlier in the run, so a pass is stable and
;; the passes together sort. `SortPass` comes from Pod.
((var uniform) (@group 0) (@binding 0) (sorting SortPass))

((var storage read) (@group 0) (@binding 1) (keys_in (array u32)))

((var storage read) (@group 0) (@binding 2) (values_in (array u32)))

((var storage read_write) (@group 0) (@binding 3) (counts (array u32)))

((var storage read_write) (@group 0) (@binding 4) (keys_out (array u32)))

((var storage read_write) (@group 0) (@binding 5) (values_out (array u32)))

((var storage read) (@group 0) (@binding 6) (counted (array u32)))

((var workgroup) (bins (array (atomic u32) 256)))

((var workgroup) (digits (array u32 256)))

((var workgroup) (starts (array u32 256)))

(fn digit ((key u32)) (-> u32)
    (return (bit-and (>> key (u32 (get sorting shift))) 255u)))

;; The keys the sort sorts.
(fn key_count () (-> u32)
    (return (min (at counted 0) (u32 (get sorting capacity)))))

;; The first block of workgroup `w`'s run, of `ws` runs, and the block
;; after its last: the blocks of 256 keys counted, shared as evenly as
;; whole runs allow.
(fn run ((w u32) (ws u32)) (-> vec2u)
    (let blocks (/ (+ (key_count) 255u) 256u))
    (let size (/ (+ blocks (- ws 1u)) ws))
    (let first (min (* w size) blocks))
    (return (vec2u first (min (+ first size) blocks))))

(fn (@compute)
    (@workgroup_size 256)
    count_digits
    (((@builtin local_invocation_id) local vec3u)
     ((@builtin workgroup_id) group vec3u)
     ((@builtin num_workgroups) groups vec3u))
    (let t (get local x))
    (let blocks (run (get group x) (get groups x)))
    (let end (min (* (get blocks y) 256u) (key_count)))
    (atomicStore (address-of (at bins t)) 0u)
    (workgroupBarrier)
    (for ((var i (+ (* (get blocks x) 256u) t)) (< i end) (+= i 256u))
         (atomicAdd (address-of (at bins (digit (at keys_in i)))) 1u))
    (workgroupBarrier)
    (= (at counts (+ (* t (get groups x)) (get group x))) (atomicLoad (address-of (at bins t)))))

;; `starts` holds where the run's next key of each digit goes. A key's
;; rank among its block's keys of the same digit is how many come before
;; it: a count over at most 255 neighbours in workgroup memory, the
;; simplest stable ranking. Keys past the count take digit 256, which no
;; key has. After a block, each digit's start moves past the block's keys
;; of that digit, which `bins` counts; a block's digits are read before
;; the next block's are written.
(fn (@compute)
    (@workgroup_size 256)
    scatter
    (((@builtin local_invocation_id) local vec3u)
     ((@builtin workgroup_id) group vec3u)
     ((@builtin num_workgroups) groups vec3u))
    (let t (get local x))
    (let blocks (run (get group x) (get groups x)))
    (= (at starts t) (at counts (+ (* t (get groups x)) (get group x))))
    (for ((var block (get blocks x)) (< block (get blocks y)) (+= block 1u))
         (let i (+ (* block 256u) t))
         (let inside (< i (key_count)))
         (var d 256u)
         (if (inside (= d (digit (at keys_in i)))))
         (= (at digits t) d)
         (atomicStore (address-of (at bins t)) 0u)
         (workgroupBarrier)
         (if (inside
              (var rank 0u)
              (for ((var j 0u) (< j t) (+= j 1u)) (if ((== (at digits j) d) (+= rank 1u))))
              (let to (+ (at starts d) rank))
              (= (at keys_out to) (at keys_in i))
              (= (at values_out to) (at values_in i))
              (atomicAdd (address-of (at bins d)) 1u)))
         (workgroupBarrier)
         (+= (at starts t) (atomicLoad (address-of (at bins t))))
         (workgroupBarrier)))
