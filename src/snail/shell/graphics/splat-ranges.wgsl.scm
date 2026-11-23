;; Where each tile's entries start and end, ends excluded, once the
;; entries asked for, `total[0]` of them at most CAPACITY, are sorted by
;; tile; a tile with none keeps 0 to 0. The threads take the entries in
;; turn, so the work is that of the entries asked for.
((var storage read) (@group 0) (@binding 0) (sorted_keys (array u32)))

((var storage read) (@group 0) (@binding 1) (total (array u32)))

((var storage read_write) (@group 0) (@binding 2) (ranges (array u32)))

(fn (@compute)
    (@workgroup_size 256)
    find_ranges
    (((@builtin global_invocation_id) gid vec3u) ((@builtin num_workgroups) nwg vec3u))
    (let count (min (at total 0) CAPACITY))
    (for ((var e (get gid x)) (< e count) (+= e (* (get nwg x) 256u)))
         (let key (at sorted_keys e))
         (let before (at sorted_keys (- (max e 1u) 1u)))
         (let after (at sorted_keys (min (+ e 1u) (- count 1u))))
         (if ((< key TILE_COUNT)
              (if ((or (== e 0u) (!= before key)) (= (at ranges (* 2u key)) e)))
              (if ((or (== e (- count 1u)) (!= after key))
                   (= (at ranges (+ (* 2u key) 1u)) (+ e 1u))))))))
