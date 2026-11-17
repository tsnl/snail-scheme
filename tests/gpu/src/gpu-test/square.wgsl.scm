;; Each number squared in place, one invocation a number.
((var storage read_write) (@group 0) (@binding 0) (numbers (array u32)))

(fn (@compute) (@workgroup_size 64) square_main (((@builtin global_invocation_id) id vec3u))
    (if ((< (get id x) (arrayLength (address-of numbers)))
         (= (at numbers (get id x)) (* (at numbers (get id x)) (at numbers (get id x)))))))
