;; An entry a tile each gaussian reaches, keyed by the tile: gaussians in
;; order of depth, each from the scanned offset of its count, so a stable
;; sort by tile leaves each tile's entries near to far. Entries past
;; CAPACITY are dropped, and nothing reads the entries past those asked
;; for.
((var storage read) (@group 0) (@binding 0) (splats (array f32)))

((var storage read) (@group 0) (@binding 1) (radii (array f32)))

((var storage read) (@group 0) (@binding 2) (order (array u32)))

((var storage read) (@group 0) (@binding 3) (offsets (array u32)))

((var storage read_write) (@group 0) (@binding 4) (keys (array u32)))

((var storage read_write) (@group 0) (@binding 5) (ids (array u32)))

(fn (@compute)
    (@workgroup_size 256)
    emit_keys
    (((@builtin global_invocation_id) gid vec3u) ((@builtin num_workgroups) nwg vec3u))
    (let j (invocation gid nwg))
    (if ((< j COUNT)
         (let g (at order j))
         (let b (* 9u g))
         (let center (vec2f (at splats b) (at splats (+ b 1u))))
         (let conic (vec3f (at splats (+ b 2u)) (at splats (+ b 3u)) (at splats (+ b 4u))))
         (let limit (reach (at splats (+ b 8u))))
         (let rect (tile_rect center conic limit (at radii g)))
         (var e (at offsets j))
         (for ((var y (get rect y)) (< y (get rect w)) (+= y 1u))
              (for ((var x (get rect x)) (< x (get rect z)) (+= x 1u))
                   (if ((reaches center conic limit (vec2u x y))
                        (if ((< e CAPACITY) (= (at keys e) (+ (* y TILES_X) x)) (= (at ids e) g)))
                        (+= e 1u))))))))
