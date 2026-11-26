;; Tone mapping: light brought into the display's range, by one of three
;; curves, which the post passes (post.wgsl.scm) and the path tracer's
;; display resolve (upscale.wgsl.scm) share:
;;
;;   0 neutral       the shoulder of Khronos's PBR Neutral curve, for light
;;                   already in display terms: a color whose largest channel
;;                   is under 0.8 passes unchanged, and a brighter one is
;;                   scaled down toward 1, keeping its hue, and desaturated
;;                   a little, as a bright light looks
;;   1 filmic        John Hable's filmic curve from Uncharted 2, for
;;                   physical light: each channel through a toe and a
;;                   shoulder, scaled so `white` maps to 1, then encoded as
;;                   sRGB, which the canvas's 8-bit format is not
;;   2 photographic  the hue-preserving shoulder applied to linear radiance,
;;                   then encoded as sRGB
(const desaturation 0.15)

(fn shoulder ((color vec3f) (knee f32)) (-> vec3f)
    (let peak (max (get color r) (max (get color g) (get color b))))
    (if ((< peak knee) (return color)))
    (let room (- 1.0 knee))
    (let top (- 1.0 (/ (* room room) (- (+ peak room) knee))))
    (let fade (- 1.0 (/ 1.0 (+ (* desaturation (- peak top)) 1.0))))
    (return (mix (* color (/ top peak)) (vec3f top) fade)))

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

;; Light through curve `curve`, as the display shows it.
(fn tone_mapped ((curve u32) (light vec3f)) (-> vec3f)
    (if ((== curve 0u) (return (shoulder light 0.8))))
    (if ((== curve 1u)
         (return (srgb (/ (hable (* (max light (vec3f 0.0)) 2.0)) (hable (vec3f white)))))))
    (return (srgb (shoulder (max light (vec3f 0.0)) 0.38))))
