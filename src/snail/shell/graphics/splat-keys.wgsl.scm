;; An entry a tile each gaussian covers, keyed by the tile: gaussians in
;; order of depth, each from the scanned offset of its count, so a stable
;; sort by tile leaves each tile's entries near to far. `pad_keys` keys
;; every unused entry with TILE_COUNT, after every tile. Entries past
;; CAPACITY are dropped.
((var storage read) (@group 0) (@binding 0) (centers (array f32)))

((var storage read) (@group 0) (@binding 1) (radii (array f32)))

((var storage read) (@group 0) (@binding 2) (order (array u32)))

((var storage read) (@group 0) (@binding 3) (offsets (array u32)))

((var storage read) (@group 0) (@binding 4) (sorted_counts (array u32)))

((var storage read_write) (@group 0) (@binding 5) (keys (array u32)))

((var storage read_write) (@group 0) (@binding 6) (ids (array u32)))

(fn (@compute)
    (@workgroup_size 256)
    emit_keys
    (((@builtin global_invocation_id) gid vec3u) ((@builtin num_workgroups) nwg vec3u))
    (let j (invocation gid nwg))
    (if ((< j COUNT)
         (let g (at order j))
         (let rect (tile_rect
                    (vec2f (at centers (* 2u g)) (at centers (+ (* 2u g) 1u)))
                    (at radii g)))
         (var e (at offsets j))
         (for ((var y (get rect y)) (< y (get rect w)) (+= y 1u))
              (for ((var x (get rect x)) (< x (get rect z)) (+= x 1u))
                   (if ((< e CAPACITY) (= (at keys e) (+ (* y TILES_X) x)) (= (at ids e) g)))
                   (+= e 1u))))))

(fn (@compute)
    (@workgroup_size 256)
    pad_keys
    (((@builtin global_invocation_id) gid vec3u) ((@builtin num_workgroups) nwg vec3u))
    (let e (invocation gid nwg))
    (let total (+ (at offsets (- COUNT 1u)) (at sorted_counts (- COUNT 1u))))
    (if ((and (< e CAPACITY) (>= e total)) (= (at keys e) TILE_COUNT))))
