;; The same point on the mapped surface across time, distance and face orientation.
((var storage read_write) (@group 0) (@binding 0) (results (array u32)))
(fn (@compute) (@workgroup_size 1) water_main ()
    (let pos (vec3f 63.0 0.0 26.0))
    (let up (vec3f 0.0 1.0 0.0))
    (let first (water_surface pos up 0.0 (water_cone up 0.05) 0.13))
    (let later (water_surface pos up 1.0 (water_cone up 0.05) 0.13))
    (= (at results 0) (select 0u 1u (> (distance first later) 0.02)))
    (= (at results 1) (select 0u 1u (< (abs (- (length (get first xyz)) 1.0)) 0.0001)))
    (let far (water_surface pos up 0.0 (water_cone up 20.0) 0.13))
    (let narrow (mat2x2f (vec2f 0.1 0.0) (vec2f 0.0 20.0)))
    (let crest (wave_slope (vec2f 0.0) (vec2f 1.0 0.0) 0.0 1.0 narrow))
    (= (at results 2)
       (select 0u
               1u
               (and (> (get crest x) 0.99)
                    (< (distance (get far xyz) up) 0.0001)
                    (> (get far w) (get first w)))))
    (= (at results 3)
       (select 0u
               1u
               (and
                (< (distance (- (get first xyz))
                             (get (water_surface pos (- up) 0.0 (water_cone up 0.05) 0.13) xyz))
                   0.0001)
                (< (abs (- (dielectric_f0 true) 0.0204)) 0.00001)))))
