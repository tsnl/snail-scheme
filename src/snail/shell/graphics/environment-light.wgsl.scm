;; An environment as light, for kernels that include this text, in group
;; 2: its radiance, and the table that samples it by its light
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

(fn environment_light ((d vec3f)) (-> vec3f)
    (return (get (textureLoad environment (environment_texel d) 0) xyz)))

(fn environment_pdf ((d vec3f)) (-> f32)
    (let size (environment_size))
    (let total (get (textureLoad environment_table size 0) x))
    (if ((<= total 0.0) (return 0.0)))
    (let lum (dot (environment_light d) (vec3f 0.2126 0.7152 0.0722)))
    (return (/ (* lum (f32 (get size x)) (f32 (get size y))) (* total 19.7392088021787))))

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

(fn environment_sample ((r vec4f)) (-> vec4f)
    (let size (environment_size))
    (if ((<= (get (textureLoad environment_table size 0) x) 0.0) (return (vec4f 0.0 1.0 0.0 0.0))))
    (let y (environment_search (get r x) (get size y) (get size x) true))
    (let x (environment_search (get r y) (get size x) y false))
    (let d (environment_direction (/ (+ (vec2f (f32 x) (f32 y)) (get r zw)) (vec2f size))))
    (return (vec4f d (environment_pdf d))))
