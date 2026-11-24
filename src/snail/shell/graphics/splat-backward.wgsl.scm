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
;; and opacity's: nine gradients, laid out as the gaussian's nine floats.
;;
;; Many pixels add to one gaussian, so the sums are made in three steps.
;; A subgroup sums its pixels' gradients, every invocation adding zero
;; where its pixel took nothing from the gaussian; one invocation of it
;; adds those into the batch's sums in workgroup memory; and once the
;; batch is walked, each invocation adds one gaussian's sums into `grads`.
;; The last two add floats with compare-and-swap loops. A tile walks only
;; as deep as its deepest pixel went, and a subgroup skips a gaussian none
;; of its pixels blended. The kernel's code starts with `enable
;; subgroups;` and turns off the subgroup uniformity diagnostic
;; (splat-train): the sums are taken where the whole subgroup agrees to.
((var storage read) (@group 0) (@binding 0) (ids (array u32)))

((var storage read) (@group 0) (@binding 1) (ranges (array u32)))

((var storage read) (@group 0) (@binding 2) (splats (array f32)))

((var storage read) (@group 0) (@binding 3) (finals (array f32)))

((var storage read) (@group 0) (@binding 4) (contributed (array u32)))

((var storage read) (@group 0) (@binding 5) (image_grads (array f32)))

((var storage read_write) (@group 0) (@binding 6) (grads (array (atomic u32))))

((var workgroup) (batch_ids (array u32 TILE_PIXELS)))

((var workgroup) (batch_centers (array vec2f TILE_PIXELS)))

((var workgroup) (batch_conics (array vec4f TILE_PIXELS)))

((var workgroup) (batch_colors (array vec3f TILE_PIXELS)))

;; The batch's sums, nine a gaussian, as float bits.
(const GRAD_SLOTS (* 9u TILE_PIXELS))

((var workgroup) (batch_grads (array (atomic u32) GRAD_SLOTS)))

((var workgroup) (deepest (atomic u32)))

((var workgroup) (reach u32))

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

;; batch_grads[index] += value, atomically.
(fn accumulate_batch ((index u32) (value f32))
    (if ((== value 0.0) (return)))
    (var old (atomicLoad (address-of (at batch_grads index))))
    (loop
     (let swapped
         (atomicCompareExchangeWeak (address-of (at batch_grads index))
                                    old
                                    ((bitcast u32) (+ ((bitcast f32) old) value))))
     (if ((get swapped exchanged) (break)))
     (= old (get swapped old_value))))

(fn (@compute)
    (@workgroup_size TILE_PIXELS)
    rasterize_backward
    (((@builtin workgroup_id) wid vec3u)
     ((@builtin num_workgroups) nwg vec3u)
     ((@builtin local_invocation_index) t u32))
    (let tile (+ (* (get wid y) (get nwg x)) (get wid x)))
    (if ((>= tile (* TILES_X TILES_Y)) (return)))
    (let px (+ (* (% tile TILES_X) TILE) (% t TILE)))
    (let py (+ (* (/ tile TILES_X) TILE) (/ t TILE)))
    (let inside (and (< px WIDTH) (< py HEIGHT)))
    (let p (select 0u (+ (* py WIDTH) px) inside))
    (let pixel (vec2f (+ (f32 px) 0.5) (+ (f32 py) 0.5)))
    (let start (at ranges (* 2u tile)))
    (let last (select 0u (at contributed p) inside))
    (if ((== t 0u) (atomicStore (address-of deepest) 0u)))
    (workgroupBarrier)
    (atomicMax (address-of deepest) last)
    (workgroupBarrier)
    (if ((== t 0u) (= reach (atomicLoad (address-of deepest)))))
    (let count (workgroupUniformLoad (address-of reach)))
    (let g (vec3f
            (at image_grads (* 3u p))
            (at image_grads (+ (* 3u p) 1u))
            (at image_grads (+ (* 3u p) 2u))))
    (var transmittance (at finals p))
    (var behind (vec3f 0.0))
    (var last_alpha 0.0)
    (var last_color (vec3f 0.0))
    (for ((var batch 0u) (< (* batch TILE_PIXELS) count) (+= batch 1u))
         (let walked (* batch TILE_PIXELS))
         (if ((< (+ walked t) count) (load_entry t (at ids (- (+ start count) (+ walked t 1u))))))
         (for ((var k 0u) (< k 9u) (+= k 1u))
              (atomicStore (address-of (at batch_grads (+ (* t 9u) k))) 0u))
         (workgroupBarrier)
         (let size (min TILE_PIXELS (- count walked)))
         (for ((var j 0u) (< j size) (+= j 1u))
              (let d (- (at batch_centers j) pixel))
              (let conic (at batch_conics j))
              (let power (-
                          (* -0.5
                             (+ (* (get conic x) (get d x) (get d x))
                                (* (get conic z) (get d y) (get d y))))
                          (* (get conic y) (get d x) (get d y))))
              (let gauss (exp (min power 0.0)))
              (let alpha (min 0.99 (* (get conic w) gauss)))
              (let blended (and inside
                                (<= (- count (+ walked j)) last)
                                (<= power 0.0)
                                (>= alpha (/ 1.0 255.0))))
              (if ((subgroupAny blended)
                   (var alpha_grad 0.0)
                   (var color_grad (vec3f 0.0))
                   (if (blended
                        (= transmittance (/ transmittance (- 1.0 alpha)))
                        (let color (at batch_colors j))
                        (= behind (+ (* last_alpha last_color) (* (- 1.0 last_alpha) behind)))
                        (= last_alpha alpha)
                        (= last_color color)
                        (= alpha_grad (* transmittance (dot (- color behind) g)))
                        (= color_grad (* (* alpha transmittance) g))))
                   (let gauss_grad (* (get conic w) alpha_grad))
                   (let gdx (* gauss (get d x)))
                   (let gdy (* gauss (get d y)))
                   (let mean_x
                       (subgroupAdd
                        (* gauss_grad (- (- (* gdx (get conic x))) (* gdy (get conic y))))))
                   (let mean_y
                       (subgroupAdd
                        (* gauss_grad (- (- (* gdy (get conic z))) (* gdx (get conic y))))))
                   (let conic_a (subgroupAdd (* -0.5 (* gdx (get d x) gauss_grad))))
                   (let conic_b (subgroupAdd (- (* gdx (get d y) gauss_grad))))
                   (let conic_c (subgroupAdd (* -0.5 (* gdy (get d y) gauss_grad))))
                   (let red (subgroupAdd (get color_grad x)))
                   (let green (subgroupAdd (get color_grad y)))
                   (let blue (subgroupAdd (get color_grad z)))
                   (let opacity (subgroupAdd (* gauss alpha_grad)))
                   (if ((subgroupElect)
                        (let base (* 9u j))
                        (accumulate_batch base mean_x)
                        (accumulate_batch (+ base 1u) mean_y)
                        (accumulate_batch (+ base 2u) conic_a)
                        (accumulate_batch (+ base 3u) conic_b)
                        (accumulate_batch (+ base 4u) conic_c)
                        (accumulate_batch (+ base 5u) red)
                        (accumulate_batch (+ base 6u) green)
                        (accumulate_batch (+ base 7u) blue)
                        (accumulate_batch (+ base 8u) opacity))))))
         (workgroupBarrier)
         (if ((< t size)
              (for ((var k 0u) (< k 9u) (+= k 1u))
                   (accumulate (+ (* 9u (at batch_ids t)) k)
                               ((bitcast f32)
                                (atomicLoad (address-of (at batch_grads (+ (* t 9u) k)))))))))
         (workgroupBarrier)))
