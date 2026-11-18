;; Where each tile's entries start and end, ends excluded, once the
;; entries are sorted by tile; a tile with none keeps 0 to 0.
((var storage read) (@group 0) (@binding 0) (sorted_keys (array u32)))

((var storage read_write) (@group 0) (@binding 1) (ranges (array u32)))

(fn (@compute)
    (@workgroup_size 256)
    find_ranges
    (((@builtin global_invocation_id) gid vec3u) ((@builtin num_workgroups) nwg vec3u))
    (let e (invocation gid nwg))
    (if ((< e CAPACITY)
         (let key (at sorted_keys e))
         (let before (at sorted_keys (- (max e 1u) 1u)))
         (let after (at sorted_keys (min (+ e 1u) (- CAPACITY 1u))))
         (if ((< key TILE_COUNT)
              (if ((or (== e 0u) (!= before key)) (= (at ranges (* 2u key)) e)))
              (if ((or (== e (- CAPACITY 1u)) (!= after key))
                   (= (at ranges (+ (* 2u key) 1u)) (+ e 1u)))))))))
