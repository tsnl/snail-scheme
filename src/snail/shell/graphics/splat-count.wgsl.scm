;; How many tiles each gaussian reaches, the tiles about its reach walked
;; in the order splat-keys emits them.
((var storage read) (@group 0) (@binding 0) (splats (array f32)))

((var storage read) (@group 0) (@binding 1) (radii (array f32)))

((var storage read_write) (@group 0) (@binding 2) (counts (array u32)))

(fn (@compute)
    (@workgroup_size 256)
    count_tiles
    (((@builtin global_invocation_id) gid vec3u) ((@builtin num_workgroups) nwg vec3u))
    (let i (invocation gid nwg))
    (if ((< i COUNT)
         (let b (* 9u i))
         (let center (vec2f (at splats b) (at splats (+ b 1u))))
         (let conic (vec3f (at splats (+ b 2u)) (at splats (+ b 3u)) (at splats (+ b 4u))))
         (let limit (reach (at splats (+ b 8u))))
         (let rect (tile_rect center conic limit (at radii i)))
         (var n 0u)
         (for ((var y (get rect y)) (< y (get rect w)) (+= y 1u))
              (for ((var x (get rect x)) (< x (get rect z)) (+= x 1u))
                   (if ((reaches center conic limit (vec2u x y)) (+= n 1u)))))
         (= (at counts i) n))))
