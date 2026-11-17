;; A separable gaussian blur of a row-major HEIGHT x WIDTH x CHANNELS image,
;; the window SSIM compares images through: `blur_rows` blurs each row
;; into `rows`, `blur_columns` each column of that into `blurred`, by the
;; 11 WEIGHTS centered on each pixel, reading zeros past the edges. The
;; weights are symmetric and the edges zero, so the blur is its own
;; adjoint. WIDTH, HEIGHT, CHANNELS and WEIGHTS come first, from
;; (snail shell graphics splat-train).
((var storage read) (@group 0) (@binding 0) (source (array f32)))

((var storage read_write) (@group 0) (@binding 1) (rows (array f32)))

((var storage read_write) (@group 0) (@binding 2) (blurred (array f32)))

(fn invocation ((gid vec3u) (nwg vec3u)) (-> u32)
    (return (+ (* (get gid y) (get nwg x) 256u) (get gid x))))

(fn (@compute)
    (@workgroup_size 256)
    blur_rows
    (((@builtin global_invocation_id) gid vec3u) ((@builtin num_workgroups) nwg vec3u))
    (let i (invocation gid nwg))
    (if ((>= i (* WIDTH HEIGHT CHANNELS)) (return)))
    (let x (i32 (% (/ i CHANNELS) WIDTH)))
    (var sum 0.0)
    (for ((var k 0) (< k 11) (+= k 1))
         (let at_x (+ x (- k 5)))
         (if ((and (>= at_x 0) (< at_x (i32 WIDTH)))
              (+= sum
                  (* (at WEIGHTS k) (at source (u32 (+ (i32 i) (* (- k 5) (i32 CHANNELS))))))))))
    (= (at rows i) sum))

(fn (@compute)
    (@workgroup_size 256)
    blur_columns
    (((@builtin global_invocation_id) gid vec3u) ((@builtin num_workgroups) nwg vec3u))
    (let i (invocation gid nwg))
    (if ((>= i (* WIDTH HEIGHT CHANNELS)) (return)))
    (let y (i32 (/ i (* CHANNELS WIDTH))))
    (var sum 0.0)
    (for ((var k 0) (< k 11) (+= k 1))
         (let at_y (+ y (- k 5)))
         (if ((and (>= at_y 0) (< at_y (i32 HEIGHT)))
              (+= sum
                  (* (at WEIGHTS k)
                     (at rows (u32 (+ (i32 i) (* (- k 5) (i32 (* CHANNELS WIDTH)))))))))))
    (= (at blurred i) sum))
