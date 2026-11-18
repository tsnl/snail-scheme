;; Six standard normal numbers a row, for sampling split gaussians'
;; children: each from a PCG hash of its index and a seed, two uniform
;; numbers at a time turned normal by Box and Muller's transform. COUNT
;; comes first, from (snail shell graphics splat-fit).
((var storage read) (@group 0) (@binding 0) (seed (array u32)))

((var storage read_write) (@group 0) (@binding 1) (normals (array f32)))

(fn hash ((value u32)) (-> u32)
    (let state (+ (* value 747796405u) 2891336453u))
    (let word (* (bit-xor (>> state (+ (>> state 28u) 4u)) state) 277803737u))
    (return (bit-xor (>> word 22u) word)))

;; A uniform number in (0, 1].
(fn uniform ((value u32)) (-> f32)
    (return (/ (+ (f32 (>> (hash value) 8u)) 1.0) 16777216.0)))

(fn (@compute)
    (@workgroup_size 256)
    sample_normals
    (((@builtin global_invocation_id) gid vec3u) ((@builtin num_workgroups) nwg vec3u))
    (let i (+ (* (get gid y) (get nwg x) 256u) (get gid x)))
    (if ((>= i (* 3u COUNT)) (return)))
    (let base (hash (bit-xor (* i 2654435761u) (at seed 0u))))
    (let radius (sqrt (* -2.0 (log (uniform base)))))
    (let angle (* 6.283185307179586 (uniform (+ base 1u))))
    (= (at normals (* 2u i)) (* radius (cos angle)))
    (= (at normals (+ (* 2u i) 1u)) (* radius (sin angle))))
