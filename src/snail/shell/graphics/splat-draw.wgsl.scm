;; Drawing projected gaussians in sorted order, far to near, an instance a
;; gaussian: a square of its radius around its center, over which the
;; fragment stage evaluates the gaussian's falloff, exp(-d^T conic d / 2)
;; at offset d in pixels, times its opacity, as the reference does, and
;; blends its color over what is drawn. A culled gaussian's radius is 0,
;; so its square has no area. `SplatCamera` and `Projected` come from Pod.
((var uniform) (@group 0) (@binding 0) (camera SplatCamera))

((var storage read) (@group 0) (@binding 1) (projected (array Projected)))

((var storage read) (@group 0) (@binding 2) (order (array u32)))

(struct SplatOut
        ((@builtin position) position vec4f)
        ((@location 0) offset vec2f)
        ((@location 1) (@interpolate flat) conic vec3f)
        ((@location 2) (@interpolate flat) color vec4f))

(fn (@vertex)
    splat_vertex
    (((@builtin vertex_index) corner u32) ((@builtin instance_index) instance u32))
    (-> SplatOut)
    (let p (at projected (at order instance)))
    (let unit (vec2f (f32 (bit-and corner 1u)) (f32 (>> corner 1u))))
    (let offset (* (- (* unit 2.0) 1.0) (get p radius)))
    (var (out SplatOut))
    (= (get out position)
       (vec4f (/ (+ (get p center) offset) (* 0.5 (get camera viewport))) 0.0 1.0))
    (= (get out offset) offset)
    (= (get out conic) (get p conic xyz))
    (= (get out color) (get p color))
    (return out))

(fn (@fragment) splat_fragment ((in SplatOut)) (-> (@location 0) vec4f)
    (let d (get in offset))
    (let c (get in conic))
    (let power (- (* -0.5 (+ (* (get c x) (get d x) (get d x)) (* (get c z) (get d y) (get d y))))
                  (* (get c y) (get d x) (get d y))))
    (if ((> power 0.0) (discard)))
    (let alpha (min 0.99 (* (get in color a) (exp power))))
    (if ((< alpha (/ 1.0 255.0)) (discard)))
    (return (vec4f (get in color rgb) alpha)))
