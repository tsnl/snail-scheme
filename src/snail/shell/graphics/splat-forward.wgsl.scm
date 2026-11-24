;; Rasterizing binned gaussians, a workgroup a 16x16 tile and an invocation
;; a pixel, as the reference's forward pass does: the tile's entries, near
;; to far, are loaded 256 at a time into workgroup memory, and each pixel
;; blends each gaussian's color by alpha = min(0.99, opacity G), G =
;; exp(-d^T conic d / 2) at offset d from the pixel's center, skipping
;; those under 1/255, until its transmittance would fall under 1e-4. The
;; background is black. Each pixel's final transmittance and how many
;; entries it went through go to `keep`, which the code before this file
;; defines: training's keeps them for the backward pass to start from
;; (splat-forward-state.wgsl.scm), and viewing's does nothing, so its
;; kernel has neither their bindings nor their stores.
;;
;; Pixel (x, y) has its center at (x + 0.5, y + 0.5). The image is
;; row-major RGB, three floats a pixel. Each gaussian is nine floats:
;; center x y, conic a b c, color r g b and opacity, the conic's power
;; being -(a dx^2 + c dy^2) / 2 - b dx dy.
((var storage read) (@group 0) (@binding 0) (ids (array u32)))

((var storage read) (@group 0) (@binding 1) (ranges (array u32)))

((var storage read) (@group 0) (@binding 2) (splats (array f32)))

((var storage read_write) (@group 0) (@binding 3) (image (array f32)))

((var workgroup) (batch_centers (array vec2f TILE_PIXELS)))

((var workgroup) (batch_conics (array vec4f TILE_PIXELS)))

((var workgroup) (batch_colors (array vec3f TILE_PIXELS)))

;; A gaussian's center, conic with its opacity, and color.
(fn load_entry ((slot u32) (g u32))
    (let b (* 9u g))
    (= (at batch_centers slot) (vec2f (at splats b) (at splats (+ b 1u))))
    (= (at batch_conics slot)
       (vec4f (at splats (+ b 2u)) (at splats (+ b 3u)) (at splats (+ b 4u)) (at splats (+ b 8u))))
    (= (at batch_colors slot)
       (vec3f (at splats (+ b 5u)) (at splats (+ b 6u)) (at splats (+ b 7u)))))

(fn (@compute)
    (@workgroup_size TILE_PIXELS)
    rasterize
    (((@builtin workgroup_id) wid vec3u)
     ((@builtin num_workgroups) nwg vec3u)
     ((@builtin local_invocation_index) t u32))
    (let tile (+ (* (get wid y) (get nwg x)) (get wid x)))
    (if ((>= tile (* TILES_X TILES_Y)) (return)))
    (let px (+ (* (% tile TILES_X) TILE) (% t TILE)))
    (let py (+ (* (/ tile TILES_X) TILE) (/ t TILE)))
    (let inside (and (< px WIDTH) (< py HEIGHT)))
    (let pixel (vec2f (+ (f32 px) 0.5) (+ (f32 py) 0.5)))
    (let start (at ranges (* 2u tile)))
    (let end (at ranges (+ (* 2u tile) 1u)))
    (var transmittance 1.0)
    (var color (vec3f 0.0))
    (var last 0u)
    (var done (not inside))
    (for ((var batch 0u) (< (+ start (* batch TILE_PIXELS)) end) (+= batch 1u))
         (let base (+ start (* batch TILE_PIXELS)))
         (if ((< (+ base t) end) (load_entry t (at ids (+ base t)))))
         (workgroupBarrier)
         (for ((var j 0u) (< j (min TILE_PIXELS (- end base))) (+= j 1u))
              (if (done (continue)))
              (let d (- (at batch_centers j) pixel))
              (let conic (at batch_conics j))
              (let power (-
                          (* -0.5
                             (+ (* (get conic x) (get d x) (get d x))
                                (* (get conic z) (get d y) (get d y))))
                          (* (get conic y) (get d x) (get d y))))
              (if ((> power 0.0) (continue)))
              (let alpha (min 0.99 (* (get conic w) (exp power))))
              (if ((< alpha (/ 1.0 255.0)) (continue)))
              (let next (* transmittance (- 1.0 alpha)))
              (if ((< next 0.0001) (= done true) (continue)))
              (+= color (* (at batch_colors j) (* alpha transmittance)))
              (= transmittance next)
              (= last (+ (* batch TILE_PIXELS) j 1u)))
         (workgroupBarrier))
    (if (inside
         (let p (+ (* py WIDTH) px))
         (= (at image (* 3u p)) (get color x))
         (= (at image (+ (* 3u p) 1u)) (get color y))
         (= (at image (+ (* 3u p) 2u)) (get color z))
         (keep p transmittance last))))
