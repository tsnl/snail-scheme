((var storage read) (@group 0) (@binding 0) (sampled (array vec4f)))
((var storage read_write) (@group 0) (@binding 1) (mean (array vec4f)))
((var uniform) (@group 0) (@binding 2) (scale f32))

(fn (@compute) (@workgroup_size 64) accumulate
    (((@builtin global_invocation_id) id vec3u) ((@builtin num_workgroups) groups vec3u))
    (let i (+ (get id x) (* (get id y) (get groups x) 64u)))
    (if ((< i (arrayLength (address-of mean))) (+= (at mean i) (* scale (at sampled i))))))
