;; An environment as light, for kernels that include this text, in group
;; 2: its radiance, the table that samples it by its light, and a solar disc
;; (environment.wgsl.scm makes both).
;;
;; The environment is equirectangular: u around from -z toward +x, v
;; from the zenith (+y) down. The table's rows are each row's cumulative
;; distribution, its last column the rows', and its corner the total
;; weight, light times sin θ. So a texel is chosen with odds in
;; proportion to its light times its solid angle, and the density a
;; direction is sampled with is its texel's light times W H over the
;; total times 2π², sin θ cancelling.
;;
;;   environment_light(d)   the radiance from direction d
;;   environment_pdf(d)     the density environment_sample gives d,
;;                          per unit solid angle
;;   environment_sample(r)  a direction for four random numbers, with
;;                          its density in w (0 when the environment is
;;                          black)
(var (@group 2) (@binding 0) (environment (texture_2d f32)))

(var (@group 2) (@binding 1) (environment_table (texture_2d f32)))

(var (@group 2) (@binding 2) (environment_disc (texture_2d f32)))

(fn environment_size () (-> vec2i)
    (return (vec2i (textureDimensions environment))))

(fn environment_uv ((d vec3f)) (-> vec2f)
    (return (vec2f (+ (/ (atan2 (get d x) (- (get d z))) 6.28318530717959) 0.5)
                   (/ (acos (clamp (get d y) -1.0 1.0)) 3.14159265358979))))

(fn environment_direction ((uv vec2f)) (-> vec3f)
    (let phi (* (- (get uv x) 0.5) 6.28318530717959))
    (let theta (* (get uv y) 3.14159265358979))
    (return (vec3f (* (sin theta) (sin phi)) (cos theta) (* (- (sin theta)) (cos phi)))))

(fn environment_texel ((d vec3f)) (-> vec2i)
    (let size (environment_size))
    (return (clamp (vec2i (* (environment_uv d) (vec2f size))) (vec2i 0) (- size (vec2i 1)))))

(fn sky_texel ((p vec2i) (size vec2i)) (-> vec3f)
    (let wrapped (vec2i
                  (% (+ (get p x) (get size x)) (get size x))
                  (clamp (get p y) 0 (- (get size y) 1))))
    (return (get (textureLoad environment wrapped 0) xyz)))

(fn filtered_sky ((d vec3f)) (-> vec3f)
    (let size (environment_size))
    (let p (- (* (environment_uv d) (vec2f size)) 0.5))
    (let corner (vec2i (floor p)))
    (let w (fract p))
    (return (mix (mix (sky_texel corner size) (sky_texel (+ corner (vec2i 1 0)) size) (get w x))
                 (mix (sky_texel (+ corner (vec2i 0 1)) size)
                      (sky_texel (+ corner (vec2i 1 1)) size)
                      (get w x))
                 (get w y))))

(fn disc_radiance ((d vec3f) (beam vec3f)) (-> vec3f)
    (let sun (textureLoad environment_disc (vec2i 0 0) 0))
    (if
     ((or (all (<= beam (vec3f 0.0))) (< (dot d (get sun xyz)) (get sun w))) (return (vec3f 0.0))))
    (return (/ beam (* 6.2831853 (- 1.0 (get sun w))))))

(fn environment_light ((d vec3f)) (-> vec3f)
    (let beam (textureLoad environment_disc (vec2i 1 0) 0))
    (if
     ((== (get beam w) 0.0) (return (get (textureLoad environment (environment_texel d) 0) xyz))))
    (return (+ (filtered_sky d) (disc_radiance d (get beam xyz)))))

;; A near-horizontal sightline through the marine boundary layer. The
;; alpha marks outdoor environments. All other scenes have vacuum here.
(fn aerial_transmission ((metres f32)) (-> vec3f)
    (let outdoor (get (textureLoad environment_disc (vec2i 1 0) 0) w))
    (return (exp (* metres outdoor (vec3f -0.000095 -0.00011 -0.00014)))))

(fn aerial_light ((d vec3f) (transmission vec3f)) (-> vec3f)
    (if ((all (>= transmission (vec3f 0.9999))) (return (vec3f 0.0))))
    (let sky (normalize (vec3f (get d x) (max 0.015 (abs (get d y))) (get d z))))
    (return (* (- 1.0 transmission) (filtered_sky sky))))

(const env_luma (vec3f 0.2126 0.7152 0.0722))

;; Texel solid angle is exactly this factor times sin(theta at its centre).
(fn sky_flux ((size vec2i)) (-> f32)
    (let total (get (textureLoad environment_table size 0) x))
    (return (* total (/ (* 12.5663706 (sin (/ 1.5707963 (f32 (get size y))))) (f32 (get size x))))))

(fn environment_pdf ((d vec3f)) (-> f32)
    (let beam (get (textureLoad environment_disc (vec2i 1 0) 0) xyz))
    (let flux (+ (sky_flux (environment_size)) (dot beam env_luma)))
    (if ((<= flux 0.0) (return 0.0)))
    (let cell (get (textureLoad environment (environment_texel d) 0) xyz))
    (return (/ (dot (+ cell (disc_radiance d beam)) env_luma) flux)))

;; The first index in [0, count) whose cumulative value reaches `u`:
;; down column `fixed` when `along_rows`, else along row `fixed`.
(fn environment_search ((u f32) (count i32) (fixed i32) (along_rows bool)) (-> i32)
    (var low 0)
    (var high (- count 1))
    (while (< low high)
           (let middle (/ (+ low high) 2))
           (let place (select (vec2i middle fixed) (vec2i fixed middle) along_rows))
           (if ((< (get (textureLoad environment_table place 0) x) u) (= low (+ middle 1)))
               (else (= high middle))))
    (return low))

(fn sample_disc ((r vec2f)) (-> vec3f)
    (let sun (textureLoad environment_disc (vec2i 0 0) 0))
    (let axis (get sun xyz))
    (let pole (select (vec3f 0.0 1.0 0.0) (vec3f 1.0 0.0 0.0) (> (abs (get axis y)) 0.9)))
    (let tangent (normalize (cross axis pole)))
    (let cos_theta (mix 1.0 (get sun w) (get r x)))
    (let ring (sqrt (max 0.0 (- 1.0 (* cos_theta cos_theta)))))
    (let phi (* 6.2831853 (get r y)))
    (return (normalize (+ (* cos_theta axis)
                          (* ring (+ (* (cos phi) tangent) (* (sin phi) (cross axis tangent))))))))

(fn environment_sample ((r vec4f)) (-> vec4f)
    (let size (environment_size))
    (let sky (sky_flux size))
    (let solar (dot (get (textureLoad environment_disc (vec2i 1 0) 0) xyz) env_luma))
    (let flux (+ sky solar))
    (if ((<= flux 0.0) (return (vec4f 0.0 1.0 0.0 0.0))))
    (let chosen (* (get r x) flux))
    (var d (vec3f 0.0))
    (if ((or (< chosen solar) (<= sky 0.0)) (= d (sample_disc (get r zw))))
        (else
         (let y (environment_search (/ (- chosen solar) sky) (get size y) (get size x) true))
         (let x (environment_search (get r y) (get size x) y false))
         (let theta (/ 3.14159265 (f32 (get size y))))
         (let up (mix (cos (* theta (f32 y))) (cos (* theta (f32 (+ y 1)))) (get r w)))
         (let u (/ (+ (f32 x) (get r z)) (f32 (get size x))))
         (= d (environment_direction (vec2f u (/ (acos (clamp up -1.0 1.0)) 3.14159265))))))
    (return (vec4f d (environment_pdf d))))
