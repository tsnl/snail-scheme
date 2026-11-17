;; The gradient of the forward pass (splat-forward), a workgroup a tile and
;; an invocation a pixel, as the reference's backward pass computes it:
;; each pixel walks its tile's entries far to near from the last it
;; blended, undoing its transmittance gaussian by gaussian from the final
;; one, T := T / (1 - alpha). Over those behind each gaussian it keeps
;; their blended color,
;;
;;   behind := alpha' color' + (1 - alpha') behind
;;
;; of the gaussian alpha', color' just behind, so the image's gradient g
;; gives
;;
;;   dL/dcolor = alpha T g             dL/dalpha = T (color - behind) . g
;;
;; and through alpha = opacity G, G = exp(power), the center's, conic's
;; and opacity's. Each gaussian's nine gradients, laid out as its nine
;; floats are, are added into `grads` with a float compare-and-swap loop,
;; since many pixels add to one gaussian.
((var storage read) (@group 0) (@binding 0) (ids (array u32)))

((var storage read) (@group 0) (@binding 1) (ranges (array u32)))

((var storage read) (@group 0) (@binding 2) (splats (array f32)))

((var storage read) (@group 0) (@binding 3) (finals (array f32)))

((var storage read) (@group 0) (@binding 4) (contributed (array u32)))

((var storage read) (@group 0) (@binding 5) (image_grads (array f32)))

((var storage read_write) (@group 0) (@binding 6) (grads (array (atomic u32))))

((var workgroup) (batch_ids (array u32 256)))

((var workgroup) (batch_centers (array vec2f 256)))

((var workgroup) (batch_conics (array vec4f 256)))

((var workgroup) (batch_colors (array vec3f 256)))

(fn load_entry ((slot u32) (g u32))
    (= (at batch_ids slot) g)
    (let b (* 9u g))
    (= (at batch_centers slot) (vec2f (at splats b) (at splats (+ b 1u))))
    (= (at batch_conics slot)
       (vec4f (at splats (+ b 2u)) (at splats (+ b 3u)) (at splats (+ b 4u)) (at splats (+ b 8u))))
    (= (at batch_colors slot)
       (vec3f (at splats (+ b 5u)) (at splats (+ b 6u)) (at splats (+ b 7u)))))

;; grads[index] += value, atomically.
(fn accumulate ((index u32) (value f32))
    (if ((== value 0.0) (return)))
    (var old (atomicLoad (address-of (at grads index))))
    (loop
     (let swapped
         (atomicCompareExchangeWeak (address-of (at grads index))
                                    old
                                    ((bitcast u32) (+ ((bitcast f32) old) value))))
     (if ((get swapped exchanged) (break)))
     (= old (get swapped old_value))))

(fn (@compute)
    (@workgroup_size 256)
    rasterize_backward
    (((@builtin workgroup_id) wid vec3u)
     ((@builtin num_workgroups) nwg vec3u)
     ((@builtin local_invocation_index) t u32))
    (let tile (+ (* (get wid y) (get nwg x)) (get wid x)))
    (if ((>= tile (* TILES_X TILES_Y)) (return)))
    (let px (+ (* (% tile TILES_X) 16u) (% t 16u)))
    (let py (+ (* (/ tile TILES_X) 16u) (/ t 16u)))
    (let inside (and (< px WIDTH) (< py HEIGHT)))
    (let p (select 0u (+ (* py WIDTH) px) inside))
    (let pixel (vec2f (+ (f32 px) 0.5) (+ (f32 py) 0.5)))
    (let start (at ranges (* 2u tile)))
    (let end (at ranges (+ (* 2u tile) 1u)))
    (let last (select 0u (at contributed p) inside))
    (let g (vec3f
            (at image_grads (* 3u p))
            (at image_grads (+ (* 3u p) 1u))
            (at image_grads (+ (* 3u p) 2u))))
    (var transmittance (at finals p))
    (var behind (vec3f 0.0))
    (var last_alpha 0.0)
    (var last_color (vec3f 0.0))
    (for ((var batch 0u) (< (+ start (* batch 256u)) end) (+= batch 1u))
         (let walked (* batch 256u))
         (if ((< (+ start walked t) end) (load_entry t (at ids (- end (+ walked t 1u))))))
         (workgroupBarrier)
         (for ((var j 0u) (< j (min 256u (- (- end start) walked))) (+= j 1u))
              (if ((> (- (- end start) (+ walked j)) last) (continue)))
              (let d (- (at batch_centers j) pixel))
              (let conic (at batch_conics j))
              (let power (-
                          (* -0.5
                             (+ (* (get conic x) (get d x) (get d x))
                                (* (get conic z) (get d y) (get d y))))
                          (* (get conic y) (get d x) (get d y))))
              (if ((> power 0.0) (continue)))
              (let gauss (exp power))
              (let alpha (min 0.99 (* (get conic w) gauss)))
              (if ((< alpha (/ 1.0 255.0)) (continue)))
              (= transmittance (/ transmittance (- 1.0 alpha)))
              (let color (at batch_colors j))
              (= behind (+ (* last_alpha last_color) (* (- 1.0 last_alpha) behind)))
              (= last_alpha alpha)
              (= last_color color)
              (let alpha_grad (* transmittance (dot (- color behind) g)))
              (let color_grad (* (* alpha transmittance) g))
              (let gauss_grad (* (get conic w) alpha_grad))
              (let gdx (* gauss (get d x)))
              (let gdy (* gauss (get d y)))
              (let base (* 9u (at batch_ids j)))
              (accumulate base (* gauss_grad (- (- (* gdx (get conic x))) (* gdy (get conic y)))))
              (accumulate (+ base 1u)
                          (* gauss_grad (- (- (* gdy (get conic z))) (* gdx (get conic y)))))
              (accumulate (+ base 2u) (* -0.5 (* gdx (get d x) gauss_grad)))
              (accumulate (+ base 3u) (- (* gdx (get d y) gauss_grad)))
              (accumulate (+ base 4u) (* -0.5 (* gdy (get d y) gauss_grad)))
              (accumulate (+ base 5u) (get color_grad x))
              (accumulate (+ base 6u) (get color_grad y))
              (accumulate (+ base 7u) (get color_grad z))
              (accumulate (+ base 8u) (* gauss alpha_grad)))
         (workgroupBarrier)))
