;; How many tiles each gaussian covers.
((var storage read) (@group 0) (@binding 0) (centers (array f32)))

((var storage read) (@group 0) (@binding 1) (radii (array f32)))

((var storage read_write) (@group 0) (@binding 2) (counts (array u32)))

(fn (@compute)
    (@workgroup_size 256)
    count_tiles
    (((@builtin global_invocation_id) gid vec3u) ((@builtin num_workgroups) nwg vec3u))
    (let i (invocation gid nwg))
    (if ((< i COUNT)
         (let center (vec2f (at centers (* 2u i)) (at centers (+ (* 2u i) 1u))))
         (= (at counts i) (rect_area (tile_rect center (at radii i)))))))
