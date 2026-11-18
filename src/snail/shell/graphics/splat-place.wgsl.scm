;; Where densification puts each gaussian: an invocation a row of the old
;; cloud writes, at each slot it fills in the new one, the row it came
;; from and how, 1 kept, 2 cloned or split's first child, 3 split's
;; second, leaving 0 at slots no row fills. Kept rows go first, at the
;; prefix sum of the rows kept before; new ones after all kept, at the
;; prefix sum of the new rows before. Slots past CAPACITY are dropped.
;; CAPACITY comes first, from (snail shell graphics splat-fit).
((var storage read) (@group 0) (@binding 0) (keep (array u32)))

((var storage read) (@group 0) (@binding 1) (fresh (array u32)))

((var storage read) (@group 0) (@binding 2) (kept_at (array u32)))

((var storage read) (@group 0) (@binding 3) (fresh_at (array u32)))

((var storage read_write) (@group 0) (@binding 4) (sources (array u32)))

((var storage read_write) (@group 0) (@binding 5) (kinds (array u32)))

(fn put ((slot u32) (row u32) (kind u32))
    (if ((< slot CAPACITY) (= (at sources slot) row) (= (at kinds slot) kind))))

(fn (@compute)
    (@workgroup_size 256)
    place_rows
    (((@builtin global_invocation_id) gid vec3u) ((@builtin num_workgroups) nwg vec3u))
    (let i (+ (* (get gid y) (get nwg x) 256u) (get gid x)))
    (if ((>= i CAPACITY) (return)))
    (let kept_total (+ (at kept_at (- CAPACITY 1u)) (at keep (- CAPACITY 1u))))
    (if ((!= (at keep i) 0u) (put (at kept_at i) i 1u)))
    (let at_new (+ kept_total (at fresh_at i)))
    (if ((>= (at fresh i) 1u) (put at_new i 2u)))
    (if ((>= (at fresh i) 2u) (put (+ at_new 1u) i 3u))))
