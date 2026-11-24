;; Differentiate wind waves in world metres. A footprint too wide to
;; resolve a wave transfers its mean square slope into the GGX lobe.
(fn wave_slope ((p vec2f) (k vec2f) (seconds f32) (steepness f32) (footprint mat2x2f)) (-> vec3f)
    (let magnitude (length k))
    (let phase (- (dot k p) (* (sqrt (* 9.81 magnitude)) seconds)))
    (let resolved (-
                   1.0
                   (smoothstep 0.6
                               2.8
                               (max (abs (dot k (at footprint 0)))
                                    (abs (dot k (at footprint 1)))))))
    (return (vec3f (* (normalize k) (* steepness resolved (cos phase)))
                   (* 0.5 steepness steepness (- 1.0 (* resolved resolved))))))

(fn water_cone ((toward vec3f) (width f32)) (-> mat2x2f)
    (let horizontal (get toward xz))
    (let major (/ horizontal (max 1e-6 (length horizontal))))
    (let axis (select major (vec2f 1.0 0.0) (< (length horizontal) 1e-6)))
    (return (mat2x2f (* axis (/ width (max 0.05 (abs (get toward y)))))
                     (* width (vec2f (- (get axis y)) (get axis x))))))

(fn water_surface
    ((position vec3f) (geometric vec3f) (seconds f32) (footprint mat2x2f) (roughness f32))
    (-> vec4f)
    (let p (get position xz))
    (let swell (wave_slope p (vec2f 0.29 0.20) seconds 0.056 footprint))
    (let chop (+ (wave_slope p (vec2f 0.72 1.06) seconds 0.105 footprint)
                 (wave_slope p (vec2f 1.78 -0.42) seconds 0.072 footprint)))
    (let ripples (+ (wave_slope p (vec2f 3.05 2.42) seconds 0.066 footprint)
                    (wave_slope p (vec2f -2.48 5.36) seconds 0.043 footprint)))
    ;; Wave packets and wind streaks change the ripple strength across the
    ;; surface. Variance follows the square of that amplitude.
    (let gust (+ 0.81 (* 0.19 (sin (- (dot p (vec2f 0.034 0.017)) (* 0.19 seconds)))
                         (cos (- (dot p (vec2f -0.019 0.043)) (* 0.13 seconds))))))
    (let slopes (+ swell (* (vec3f gust gust (* gust gust)) (+ chop ripples))))
    (let normal (normalize (vec3f (- (get slopes x)) 1.0 (- (get slopes y)))))
    (return (vec4f (select (- normal) normal (>= (get geometric y) 0.0))
                   (min 1.0 (pow (+ (pow roughness 4.0) (get slopes z)) 0.25)))))

;; Normal-incidence Fresnel reflectance, ((n - 1) / (n + 1))^2.
(fn dielectric_f0 ((water bool)) (-> f32)
    (return (select 0.04 0.0204 water)))
