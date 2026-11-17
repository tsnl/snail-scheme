;; Lighting a surface under the sun: Cook-Torrance with a GGX distribution,
;; Smith-Schlick shadowing and Schlick's Fresnel, plus the ambient light on
;; the diffuse color and a metal's specular color. A dielectric reflects 4%
;; at normal incidence. A face seen from behind is lit as its front. Glow
;; mixes toward the unlit color. `Sun` comes from Pod: its direction toward
;; the light and strength, then the ambient light.
(const PI 3.14159265)

(fn lit
    ((base vec3f)
     (normal vec3f)
     (view vec3f)
     (metalness f32)
     (rough f32)
     (glow f32)
     (sun Sun))
    (-> vec3f)
    (let roughness (clamp rough 0.04 1.0))
    (let front (normalize normal))
    (let n (select front (- front) (< (dot front view) 0.0)))
    (let l (normalize (get sun direction xyz)))
    (let h (normalize (+ l view)))
    (let nl (max (dot n l) 0.0))
    (let nv (max (dot n view) 1e-4))
    (let nh (max (dot n h) 0.0))
    (let vh (max (dot view h) 0.0))
    (let f0 (mix (vec3f 0.04) base metalness))
    (let fresnel (+ f0 (* (- 1.0 f0) (pow (- 1.0 vh) 5.0))))
    (let a2 (* roughness roughness roughness roughness))
    (let distribution (/ a2 (* PI (pow (+ (* nh nh (- a2 1.0)) 1.0) 2.0))))
    (let k (/ (* (+ roughness 1.0) (+ roughness 1.0)) 8.0))
    (let shadowing (* (/ nv (+ (* nv (- 1.0 k)) k)) (/ nl (+ (* nl (- 1.0 k)) k))))
    (let specular (/ (* distribution shadowing fresnel) (* 4.0 nv (max nl 1e-4))))
    (let diffuse (* (- 1.0 metalness) base))
    (let light (+ (* (+ diffuse (* PI specular)) (get sun direction w) nl)
                  (* (get sun ambient) (+ diffuse (* metalness f0)))))
    (return (mix light base glow)))
