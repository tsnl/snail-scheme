;; Read the environment that the renderer actually samples. Compare energy
;; and colour across weather changes on the same bound textures.
((var storage read_write) (@group 0) (@binding 0) (results (array u32)))
(fn (@compute) (@workgroup_size 1) sky_main ()
    (let zenith (environment_light (vec3f 0.0 1.0 0.0)))
    (let sun (get (textureLoad environment_disc (vec2i 1 0) 0) xyz))
    (= (at results 0) (select 0u 1u (> (get zenith b) (* 1.5 (get zenith r)))))
    (= (at results 1) (select 0u 1u (> (get sun r) (* 2.0 (get sun b)))))
    (= (at results 2) (u32 (* 1000.0 (sky_flux (environment_size)))))
    (= (at results 3) (u32 (* 1000.0 (dot sun env_luma))))
    (let sample (environment_sample (vec4f 0.0 0.37 0.46 0.57)))
    (let density (environment_pdf (get sample xyz)))
    (= (at results 4) (select 0u 1u (and (> density 0.0) (== density (get sample w))
                                         (< (abs (- (length (get sample xyz)) 1.0)) 0.00001)))))
