;; Drive the same accumulator as the tracer with known replacement draws.
(fn weighted_stream () (-> bool)
    (let x (LightSample (vec3f 1.0 0.0 0.0) 2.0))
    (let y (LightSample (vec3f 0.0 1.0 0.0) 4.0))
    (var (r Reservoir))
    (reservoir_draw (address-of r) x 0.25 0.5)
    (reservoir_draw (address-of r) (LightSample) 0.0 0.0)
    (reservoir_draw (address-of r) y 0.5 0.75)
    (if ((or (!= (get r selected direction x) 1.0) (!= (get r weight_sum) 16.0)) (return false)))
    (reservoir_draw (address-of r) y 0.5 0.25)
    (if ((or (!= (get r selected direction y) 1.0) (!= (reservoir_weight r) 1.5)) (return false)))
    (var (merged Reservoir))
    (= (get r emitter) 19)
    (= (get r coordinates) 65538)
    (reservoir_merge (address-of merged) r 2.0 2 0.5)
    (reservoir_merge (address-of merged) r 0.0 4 0.0)
    (return (and (== (get merged emitter) 19) (== (get merged coordinates) 65538)
                 (== (get merged count) 6) (== (get merged weight_sum) 6.0)
                 (== (reservoir_weight merged) 0.5) (== (reservoir_weight (Reservoir)) 0.0))))

((var storage read) (@group 0) (@binding 0) (history (array SurfaceReservoir)))

((var storage read_write) (@group 0) (@binding 1) (result (array vec4u 4)))

(var (@group 0) (@binding 2) (noisy (texture_2d f32)))

(var (@group 0) (@binding 3) (filtered (texture_2d f32)))

((var storage read) (@group 0) (@binding 4) (primary_shadows u32))

(var (@group 0) (@binding 5) (moments (texture_2d f32)))

;; Count fresh paths on each parity, including the last column of an odd image.
(fn coverage () (-> vec2u)
    (let size (textureDimensions noisy))
    (var fresh (vec2u 0u))
    (for ((var y 0u) (< y (get size y)) (+= y 1u))
         (for ((var x 0u) (< x (get size x)) (+= x 1u))
              (if ((> (get (textureLoad noisy (vec2u x y) 0) w) 0.0)
                   (+= (at fresh (bit-and (+ x y) 1u)) 1u)))))
    (return fresh))

(fn (@compute) (@workgroup_size 1) inspect ()
    (let r (get (at history (/ (arrayLength (address-of history)) 2u)) reservoir))
    (let w (reservoir_weight r))
    ;; Unit irradiance at 45 degrees on the matte white wall gives about
    ;; cos(45)/pi. Missing the shadow contribution or counting it twice
    ;; puts the raw radiance outside this interval.
    (let rgb (get (textureLoad noisy (vec2i (/ (textureDimensions noisy) 2u)) 0) xyz))
    (let size (textureDimensions noisy))
    (var raw (vec2f 0.0))
    (for ((var y 0u) (< y (get size y)) (+= y 1u))
         (for ((var x 0u) (< x (get size x)) (+= x 1u))
              (let red (get (textureLoad noisy (vec2u x y) 0) x))
              (+= raw (vec2f red (* red red)))))
    (= (at result 3) (vec4u ((bitcast vec2u) (/ raw (f32 (* (get size x) (get size y)))))
                            (u32 (get r emitter)) ((bitcast u32) (get r selected direction x))))
    (var brightness 2u)
    (if ((all (== rgb (vec3f 0.0))) (= brightness 0u))
        ((and (all (> rgb (vec3f 0.14))) (all (< rgb (vec3f 0.34)))) (= brightness 1u)))
    (let light (get (textureLoad filtered (vec2i (/ (textureDimensions noisy) 2u)) 0) xyz))
    (let fresh (coverage))
    ;; This wall sees the sun at every pixel, hence one shadow per new path.
    (let covered (== primary_shadows (+ (get fresh x) (get fresh y))))
    (let lit (and (all (> light (vec3f 0.14))) (all (< light (vec3f 0.34)))))
    (let age (get (textureLoad moments (vec2i (/ (textureDimensions moments) 2u)) 0) z))
    (= (at result 2) (vec4u (u32 age) (u32 (get r count)) 0u 0u))
    (= (at result 1) (vec4u fresh (u32 (and covered lit)) (u32 (get r count))))
    (= (at result 0) (vec4u (u32 (get r count)) (u32 (> w 0.0)) brightness
                            (u32 (and (>= w 0.0) (< w 1e30) (weighted_stream))))))
