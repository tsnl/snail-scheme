;; Outdoor radiance in scene-linear RGB. Distances are kilometres above a
;; spherical Earth. The sky texture holds scattered light. The unscattered
;; solar disc has its own sampler so its energy survives any texture size.
(const earth 6371.0)
(const rayleigh (vec3f 0.0058 0.0135 0.0331))
(const aerosol 0.0045)
(const solar (vec3f 10.2 10.0 9.7))
(const night_sky (vec3f 0.00046 0.00070 0.00125))

;; Positive distance to a sphere above an observer at sea level. This
;; form avoids subtracting two nearly equal radii at the zenith.
(fn shell_distance ((up f32) (height f32)) (-> f32)
    (let b (* earth up))
    (let c (* height (+ (* 2.0 earth) height)))
    (return (/ c (+ (sqrt (+ (* b b) c)) b))))

(fn air_density ((h f32)) (-> vec2f)
    (return (exp (* (max 0.0 h) (vec2f -0.125 -0.8333333)))))

(fn extinction ((column vec2f)) (-> vec3f)
    (return (+ (* rayleigh (get column x)) (vec3f (* aerosol (get column y))))))

(const ozone (vec3f 0.00065 0.00188 0.000085))

;; The ozone band absorbs mostly green and orange light on long twilight
;; paths. Use the chord through a uniform shell between 15 and 35 km.
(fn ozone_column ((h f32) (mu f32)) (-> f32)
    (let b (* (+ earth h) mu))
    (let low (sqrt (max 0.0 (+ (* b b) (* (- 15.0 h) (+ (* 2.0 earth) 15.0 h))))))
    (let high (sqrt (max 0.0 (+ (* b b) (* (- 35.0 h) (+ (* 2.0 earth) 35.0 h))))))
    (return (+ (- (max 0.0 (- high b)) (max 0.0 (- low b)))
               (- (max 0.0 (- (- low) b)) (max 0.0 (- (- high) b))))))

;; Chapman slant columns. At the tangent, an exponential atmosphere has
;; column sqrt(pi R H / 2). On the night side integrate both sides of the
;; tangent, unless the ray meets the solid Earth.
(fn sun_path ((h f32) (mu f32)) (-> vec3f)
    (let scales (vec2f 8.0 1.2))
    (let k (/ (* 2.0 scales) (* PI earth)))
    (let column (/ (* scales (air_density h)) (sqrt (+ (* mu mu) (* k (- 1.0 (* mu mu)))))))
    (var optical column)
    (if ((< mu 0.0)
         (let tangent (-
                       h
                       (* (+ earth h) (/ (* mu mu) (+ 1.0 (sqrt (max 0.0 (- 1.0 (* mu mu)))))))))
         (if ((< tangent 0.0) (return (vec3f 0.0))))
         (= optical (- (/ (* 2.0 scales (air_density tangent)) (sqrt k)) column))))
    (return (exp (- (+ (extinction optical) (* ozone (ozone_column h mu)))))))

(fn hg ((cosine f32) (g f32)) (-> f32)
    (let d (- (+ 1.0 (* g g)) (* 2.0 g cosine)))
    (return (/ (- 1.0 (* g g)) (* 4.0 PI d (sqrt d)))))

(fn clear_sky ((d vec3f) (sun vec3f)) (-> vec3f)
    (let mu (dot d sun))
    (let molecular (* rayleigh (* (/ 3.0 (* 16.0 PI)) (+ 1.0 (* mu mu)))))
    (let haze (* aerosol 0.93 (hg mu 0.76)))
    (let extent (shell_distance (get d y) 80.0))
    (var column (vec2f 0.0))
    (var ozone_depth 0.0)
    (var light (vec3f 0.0))
    (var near 0.0)
    (for ((var i 1) (<= i 12) (+= i 1))
         (let u (/ (f32 i) 12.0))
         (let far (* extent u u))
         (let t (* 0.5 (+ near far)))
         (let h (+ (* t (get d y)) (/ (* t t (- 1.0 (* (get d y) (get d y)))) (* 2.0 earth))))
         (let mass (* (air_density h) (- far near)))
         (let sun_up (/ (+ (* earth (get sun y)) (* t mu)) (+ earth h)))
         (let band (* (- far near) (smoothstep 12.0 18.0 h) (- 1.0 (smoothstep 32.0 38.0 h))))
         (let optical (+
                       (extinction (+ column (* 0.5 mass)))
                       (* ozone (+ ozone_depth (* 0.5 band)))))
         (let transmission (* (sun_path h sun_up) (exp (- optical))))
         (+= ozone_depth band)
         (+= light (* transmission (+ (* molecular (get mass x)) (vec3f (* haze (get mass y))))))
         (+= column mass)
         (= near far))
    ;; A diffuse source approximates higher orders of scattering, especially
    ;; along the horizon where the view travels many optical depths.
    (let multiple (* (vec3f 0.20 0.29 0.48) (smoothstep -0.13 0.26 (get sun y))))
    ;; City light scattered close to the horizon fades toward the clear zenith.
    (let city (* (vec3f 0.0028 0.0017 0.0010) (exp (* -7.0 (get d y)))
                 (- 1.0 (smoothstep -0.21 0.0 (get sun y)))))
    (return (+ night_sky city (* solar light) (* multiple (- 1.0 (exp (- (extinction column))))))))

;; ---- Marine cloud layer ----

;; A smooth three-dimensional lattice field. Offset octaves break
;; up the broad banks into billows. All directions see the same wind.
(fn cloud_hash ((i vec3u)) (-> f32)
    (var h (+ (* (get i x) 1597334677u) (* (get i y) 3812015801u) (* (get i z) 2798796415u)))
    (= h (* (bit-xor h (>> h 16u)) 2246822519u))
    (return (* (f32 (bit-xor h (>> h 13u))) 2.3283064365387e-10)))

(fn cloud_noise ((p vec3f)) (-> f32)
    (let i (vec3u (vec3i (floor p))))
    (let f (fract p))
    (let w (* f f (- 3.0 (* 2.0 f))))
    (let lo (mix (mix (cloud_hash i) (cloud_hash (+ i (vec3u 1 0 0))) (get w x))
                 (mix (cloud_hash (+ i (vec3u 0 1 0))) (cloud_hash (+ i (vec3u 1 1 0))) (get w x))
                 (get w y)))
    (let hi (mix (mix (cloud_hash (+ i (vec3u 0 0 1))) (cloud_hash (+ i (vec3u 1 0 1))) (get w x))
                 (mix (cloud_hash (+ i (vec3u 0 1 1))) (cloud_hash (+ i (vec3u 1 1 1))) (get w x))
                 (get w y)))
    (return (mix lo hi (get w z))))

(const cloud_base 0.65)
(const cloud_top 1.85)

(fn cloud_density ((p vec3f) (detail bool)) (-> f32)
    (let altitude (+ (get p y) (/ (dot (get p xz) (get p xz)) (* 2.0 earth))))
    (let h (/ (- altitude cloud_base) (- cloud_top cloud_base)))
    (if ((or (<= h 0.0) (>= h 1.0)) (return 0.0)))
    (let q (+ (* (+ (vec3f (get p x) altitude (get p z))
                    (vec3f (get shape weather x) 0.0 (get shape weather y))) (vec3f 0.39 0.72 0.39))
              (vec3f 0.0 12.46 0.0)))
    (let bank (+ (* 0.49 (cloud_noise q)) (* 0.27 (cloud_noise (+ (* q 2.11) 13.8)))
                 (* 0.14 (cloud_noise (+ (* q 4.37) 28.2)))))
    ;; Shadow steps span the smallest billows. Use their mean density.
    (var billows 0.05)
    (if
     (detail (= billows (+ (* 0.072 (cloud_noise (* q 9.17))) (* 0.028 (cloud_noise (* q 18.8)))))))
    (let field (+ bank billows))
    (let edge (+ (- 0.73 (* 0.35 (get shape weather z)))
                 (* 0.17 (pow (abs (- (* 2.0 h) 1.0)) 2.0))))
    (return (* 12.0 (smoothstep edge (+ edge 0.17) field) (smoothstep 0.0 0.10 h))))

;; Growing steps through the bank catch nearby self-shadow and the next
;; billow. Far along a grazing ray, the atmosphere hides cloud contrast.
(fn cloud_sun ((p vec3f) (sun vec3f)) (-> f32)
    (var tau 0.0)
    (var t 0.0)
    (var step 0.14)
    (for ((var i 0) (< i 5) (+= i 1))
         (+= tau (* step (cloud_density (+ p (* sun (+ t (* 0.5 step)))) false)))
         (+= t step)
         (*= step 1.8))
    (return (exp (- tau))))

(fn cloud_interval ((up f32)) (-> vec2f)
    (return (vec2f (shell_distance up cloud_base) (min 68.0 (shell_distance up cloud_top)))))

(fn clouded_sky ((d vec3f) (sun vec3f) (clear vec3f)) (-> vec3f)
    (let range (cloud_interval (get d y)))
    (let ds (/ (- (get range y) (get range x)) 32.0))
    (if ((or (<= ds 0.0) (<= (get shape weather z) 0.0)) (return clear)))
    (let daylight (smoothstep -0.105 0.20 (get sun y)))
    (let fill (+ (vec3f 0.0040 0.0029 0.0022) (* daylight (vec3f 0.45 0.58 0.81))))
    (let beam (* solar (sun_path 1.3 (get sun y))))
    (let mu (dot d sun))
    (let phase (+ (* 0.8 (hg mu 0.55)) (* 0.2 (hg mu -0.26))))
    (var through 1.0)
    (var light (vec3f 0.0))
    (for ((var i 0) (< i 32) (+= i 1))
         (let t (+ (get range x) (* (+ (f32 i) 0.5) ds)))
         (let p (* d t))
         (let density (cloud_density p true))
         (if ((> density 0.001)
              (let opacity (- 1.0 (exp (- (* density ds)))))
              (let visible (cloud_sun p sun))
              ;; Optical depth overhead gives a dense underside less skylight
              ;; than a thin, eroded edge at the same altitude.
              (let overhead (cloud_density (+ p (vec3f 0.0 0.33 0.0)) false))
              (let sky_fill (*
                             fill
                             (+ 0.32 (* 0.68 (exp (- (+ (* 0.16 density) (* 0.38 overhead))))))))
              (let scatter (+ sky_fill (* beam (+ (* phase visible) (* 0.12 (sqrt visible))))))
              (+= light (* through opacity (mix clear scatter (exp (* -0.032 t)))))
              (*= through (- 1.0 opacity))
              (if ((< through 0.006) (break))))))
    (return (+ light (* through clear))))

(fn outdoor_light ((direction vec3f)) (-> vec3f)
    (let sun (normalize (get shape sun xyz)))
    (let up (get direction y))
    (let day (smoothstep -0.11 0.23 (get sun y)))
    (let ground (+ (* night_sky 0.55) (* day (vec3f 0.085 0.090 0.081))))
    (if ((< up -0.065) (return ground)))
    (let d (normalize (vec3f (get direction x) (max 0.0 up) (get direction z))))
    (return (mix ground (clouded_sky d sun (clear_sky d sun)) (smoothstep -0.065 0.0 up))))

(fn (@compute) (@workgroup_size 8 8) atmosphere (((@builtin global_invocation_id) id vec3u))
    (let size (vec2u (get shape size zw)))
    (if ((any (>= (get id xy) size)) (return)))
    (let d (direction_at (/ (+ (vec2f (get id xy)) 0.5) (vec2f size))))
    (textureStore radiance (vec2i (get id xy)) (vec4f (outdoor_light d) 1.0)))

;; Only the direct beam goes in this disc. Cloud scattering is already
;; in the sky. A disabled disc has zero irradiance, including for HDR files.
(fn (@compute) (@workgroup_size 1) solar_disc ()
    (let sun (normalize (get shape sun xyz)))
    ;; Equinox full moon opposite the sun. Atmospheric extinction at the
    ;; horizon fades either source as it rises or sets.
    (let moon (< (get sun y) -0.00465))
    (let axis (select sun (- sun) moon))
    ;; Fraction of the solar disc above the geometric horizon.
    (let height (clamp (/ (get axis y) 0.00465) -1.0 1.0))
    (let visible (/ (+ (acos (- height)) (* height (sqrt (max 0.0 (- 1.0 (* height height)))))) PI))
    (var beam (vec3f 0.0))
    (if ((> (get shape weather w) 0.0)
         (= beam (* (select solar (vec3f 0.000027 0.000025 0.000022) moon)
                    visible (sun_path 0.0 (max 0.0 (get axis y)))))
         (if ((> (get shape weather z) 0.0)
              (let range (cloud_interval (max 0.0 (get axis y))))
              (let ds (/ (max 0.0 (- (get range y) (get range x))) 32.0))
              (var tau 0.0)
              (for ((var i 0) (< i 32) (+= i 1))
                   (let t (+ (get range x) (* (+ (f32 i) 0.5) ds)))
                   (+= tau (* ds (cloud_density (* axis t) true))))
              (*= beam (exp (- tau)))))))
    (textureStore disc (vec2i 0 0) (vec4f axis (get shape sun w)))
    (textureStore disc (vec2i 1 0) (vec4f beam (get shape weather w))))
