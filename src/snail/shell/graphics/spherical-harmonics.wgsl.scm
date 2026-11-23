;; Sixteen RGB coefficients per site, in coefficient-major order. The caller
;; binds harmonics and supplies its unit viewing direction.
(fn coefficient ((i u32) (k u32)) (-> vec3f)
    (let base (+ (* i 48u) (* k 3u)))
    (return (vec3f (at harmonics base) (at harmonics (+ base 1u)) (at harmonics (+ base 2u)))))

;; Real spherical harmonics to degree 3 in direction d, with the constants
;; and signs of the reference implementation, offset by 0.5.
(fn shade ((i u32) (d vec3f)) (-> vec3f)
    (let x (get d x))
    (let y (get d y))
    (let z (get d z))
    (let xx (* x x))
    (let yy (* y y))
    (let zz (* z z))
    (var c (* 0.28209479177387814 (coefficient i 0u)))
    (+= c
        (* 0.4886025119029199
           (+ (- (* y (coefficient i 1u))) (* z (coefficient i 2u)) (- (* x (coefficient i 3u))))))
    (+= c
        (+ (* 1.0925484305920792 x y (coefficient i 4u))
           (* -1.0925484305920792 y z (coefficient i 5u))
           (* 0.31539156525252005 (- (* 2.0 zz) xx yy) (coefficient i 6u))
           (* -1.0925484305920792 x z (coefficient i 7u))
           (* 0.5462742152960396 (- xx yy) (coefficient i 8u))))
    (+= c
        (+ (* -0.5900435899266435 y (- (* 3.0 xx) yy) (coefficient i 9u))
           (* 2.890611442640554 x y z (coefficient i 10u))
           (* -0.4570457994644658 y (- (* 4.0 zz) xx yy) (coefficient i 11u))
           (* 0.3731763325901154 z (- (* 2.0 zz) (* 3.0 xx) (* 3.0 yy)) (coefficient i 12u))
           (* -0.4570457994644658 x (- (* 4.0 zz) xx yy) (coefficient i 13u))
           (* 1.445305721320277 z (- xx yy) (coefficient i 14u))
           (* -0.5900435899266435 x (- xx (* 3.0 yy)) (coefficient i 15u))))
    (return (max (+ c 0.5) (vec3f 0.0))))
