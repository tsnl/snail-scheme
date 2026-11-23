;; From the frame's light to the screen, two full-screen triangles. Tone
;; mapping brings the light into range by one of two curves:
;;
;;   tone_fragment    the shoulder of Khronos's PBR Neutral curve, for
;;                    light already in display terms: a color whose
;;                    largest channel is under `knee` passes unchanged,
;;                    and a brighter one is scaled down toward 1, keeping
;;                    its hue, and desaturated a little, as a bright light
;;                    looks
;;   filmic_fragment  John Hable's filmic curve from Uncharted 2, for
;;                    physical light: each channel through a toe and a
;;                    shoulder, scaled so `white` maps to 1, then encoded
;;                    as sRGB, which the canvas's 8-bit format is not
;;
;; FXAA then softens
;; the edges of what was drawn: it finds an edge's direction from the
;; brightness of the four diagonal neighbors and blends along it (Timothy
;; Lottes's FXAA, the reduced form many WebGL renderers use).
(var (@group 0) (@binding 0) (light (texture_2d f32)))

(var (@group 0) (@binding 1) (toned (texture_2d f32)))

(var (@group 0) (@binding 2) (bilinear sampler))

(const knee 0.8)

(const desaturation 0.15)

(struct ScreenPoint ((@builtin position) position vec4f) ((@location 0) uv vec2f))

(fn (@vertex) post_vertex (((@builtin vertex_index) corner u32)) (-> ScreenPoint)
    (let unit (vec2f (f32 (bit-and corner 1u)) (f32 (>> corner 1u))))
    (return (ScreenPoint (vec4f (- (* unit 4.0) 1.0) 0.0 1.0)
                         (vec2f (* 2.0 (get unit x)) (- 1.0 (* 2.0 (get unit y)))))))

(fn shoulder ((color vec3f)) (-> vec3f)
    (let peak (max (get color r) (max (get color g) (get color b))))
    (if ((< peak knee) (return color)))
    (let room (- 1.0 knee))
    (let top (- 1.0 (/ (* room room) (- (+ peak room) knee))))
    (let fade (- 1.0 (/ 1.0 (+ (* desaturation (- peak top)) 1.0))))
    (return (mix (* color (/ top peak)) (vec3f top) fade)))

(fn (@fragment) tone_fragment (((@builtin position) position vec4f)) (-> (@location 0) vec4f)
    (let texel (textureLoad light (vec2i (get position xy)) 0))
    (return (vec4f (shoulder (get texel rgb)) 1.0)))

;; Hable's curve: shoulder strength, linear strength and angle, toe
;; strength, numerator and denominator; the light is doubled first, as
;; in his, and the white point is 11.2.
(fn hable ((x vec3f)) (-> vec3f)
    (let a 0.15)
    (let b 0.5)
    (let c 0.1)
    (let d 0.2)
    (let e 0.02)
    (let f 0.3)
    (return (- (/ (+ (* x (+ (* a x) (* c b))) (* d e)) (+ (* x (+ (* a x) b)) (* d f))) (/ e f))))

(const white 11.2)

(fn srgb ((linear vec3f)) (-> vec3f)
    (let c (clamp linear (vec3f 0.0) (vec3f 1.0)))
    (return
     (select (- (* 1.055 (pow c (vec3f (/ 1.0 2.4)))) 0.055) (* c 12.92) (<= c (vec3f 0.0031308)))))

(fn (@fragment) filmic_fragment (((@builtin position) position vec4f)) (-> (@location 0) vec4f)
    (let texel (textureLoad light (vec2i (get position xy)) 0))
    (let mapped (/ (hable (* (max (get texel rgb) (vec3f 0.0)) 2.0)) (hable (vec3f white))))
    (return (vec4f (srgb mapped) 1.0)))

(fn luma ((color vec3f)) (-> f32)
    (return (dot color (vec3f 0.299 0.587 0.114))))

(fn tap ((place vec2f)) (-> vec3f)
    (return (get (textureSampleLevel toned bilinear place 0.0) rgb)))

(fn (@fragment) fxaa_fragment (((@location 0) uv vec2f)) (-> (@location 0) vec4f)
    (let texel (/ (vec2f 1.0) (vec2f (textureDimensions toned))))
    (let m (luma (tap uv)))
    (let nw (luma (tap (+ uv (* (vec2f -1.0 -1.0) texel)))))
    (let ne (luma (tap (+ uv (* (vec2f 1.0 -1.0) texel)))))
    (let sw (luma (tap (+ uv (* (vec2f -1.0 1.0) texel)))))
    (let se (luma (tap (+ uv (* (vec2f 1.0 1.0) texel)))))
    (let low (min m (min (min nw ne) (min sw se))))
    (let high (max m (max (max nw ne) (max sw se))))
    (let edge (vec2f (- (+ sw se) (+ nw ne)) (- (+ nw sw) (+ ne se))))
    (let reduce (max (* (+ nw ne sw se) (/ 0.25 8.0)) (/ 1.0 128.0)))
    (let scale (/ 1.0 (+ (min (abs (get edge x)) (abs (get edge y))) reduce)))
    (let along (* (clamp (* edge scale) (vec2f -8.0) (vec2f 8.0)) texel))
    (let near (* 0.5 (+ (tap (- uv (* along (/ 1.0 6.0)))) (tap (+ uv (* along (/ 1.0 6.0)))))))
    (let far (+ (* near 0.5) (* 0.25 (+ (tap (- uv (* along 0.5))) (tap (+ uv (* along 0.5)))))))
    (let lf (luma far))
    (if ((or (< lf low) (> lf high)) (return (vec4f near 1.0))))
    (return (vec4f far 1.0)))
