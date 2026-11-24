;; Water stays on its mapped triangles. Differentiate travelling waves in
;; world metres to shade their slopes. Fade slopes as their wavelength falls below one sample.
(fn wave_slope ((p vec2f) (k vec2f) (seconds f32) (rate f32) (steepness f32) (width f32)) (-> vec2f)
    (let phase (- (dot k p) (* rate seconds)))
    (let resolved (- 1.0 (smoothstep 0.55 2.6 (* width (length k)))))
    (return (* (normalize k) (* steepness (* resolved (cos phase))))))

(fn water_normal ((position vec3f) (geometric vec3f) (seconds f32) (width f32)) (-> vec3f)
    (let p (get position xz))
    (let slope (+ (+ (wave_slope p (vec2f 0.72 1.06) seconds 1.5 0.16 width)
                     (wave_slope p (vec2f -2.3 0.92) seconds 2.2 0.095 width))
                  (wave_slope p (vec2f 3.8 5.2) seconds 3.4 0.06 width)))
    (let normal (normalize (vec3f (- (get slope x)) 1.0 (- (get slope y)))))
    (return (select (- normal) normal (>= (get geometric y) 0.0))))
