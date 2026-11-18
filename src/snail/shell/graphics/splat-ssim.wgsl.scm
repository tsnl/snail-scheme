;; SSIM of two row-major HEIGHT x WIDTH x CHANNELS images, x and y, fused
;; into a forward and a backward kernel, as fused-ssim does (Mallick et
;; al., 2024), so no blurred moment ever fills a buffer. A workgroup takes
;; a 16x16 tile of pixels, a channel at a time: it loads the tile and a
;; border of 5 pixels, zeros past the image's edges, blurs rows and then
;; columns by the 11 WEIGHTS in workgroup memory, and each invocation
;; finishes its pixel.
;;
;; At each pixel the blurred moments mu_x, mu_y, E[xx], E[yy] and E[xy]
;; give, with sigma_xy = E[xy] - mu_x mu_y and the like,
;;
;;   S = (2 mu_x mu_y + C1)(2 sigma_xy + C2)
;;       / ((mu_x^2 + mu_y^2 + C1)(sigma_x^2 + sigma_y^2 + C2))
;;     = A1 A2 / (B1 B2)
;;
;; and `ssim_forward` keeps S and its derivatives by the moments x moves:
;;
;;   dS/dmu_x  = 2 mu_y (A2 - A1) / (B1 B2) - 2 mu_x S (1/B1 - 1/B2)
;;   dS/dE[xx] = -S / B2              dS/dE[xy] = 2 A1 / (B1 B2)
;;
;; Each moment is a blur, symmetric with zero edges and so its own
;; adjoint, of x, x^2 or x y, so for the gradient g of S, `ssim_backward`
;; blurs g times each derivative, b1, b2 and b3, and
;;
;;   dL/dx = b1 + 2 x b2 + y b3.
;;
;; The loops over a tile's border are a fixed number of rounds, so every
;; barrier is reached by the whole workgroup. This file holds what the two
;; kernels share; splat-ssim-forward and splat-ssim-backward follow it,
;; each with its own bindings past the two images. WIDTH, HEIGHT,
;; CHANNELS, TILES_X, TILES_Y and WEIGHTS come first, from (snail shell
;; graphics splat-train).
((var storage read) (@group 0) (@binding 0) (x (array f32)))

((var storage read) (@group 0) (@binding 1) (y (array f32)))

;; A tile and its border: 26 x 26 pixels. Rows blurred: 26 rows of 16.
(const SIDE 26u)

(const AREA 676u)

(const BAND 416u)

(const C1 0.0001)

(const C2 0.0009)

;; Two images' tiles, or three products', and their blurred rows.
((var workgroup) (tile_a (array f32 2028)))

((var workgroup) (tile_b (array f32 676)))

((var workgroup) (rows (array f32 2080)))

;; The image index of a tile's pixel k of AREA in channel c, and whether
;; it is inside the image.
(fn border_index ((origin vec2u) (k u32) (c u32)) (-> vec2u)
    (let gx (- (+ (i32 (get origin x)) (i32 (% k SIDE))) 5))
    (let gy (- (+ (i32 (get origin y)) (i32 (/ k SIDE))) 5))
    (let inside (and (>= gx 0) (< gx (i32 WIDTH)) (>= gy 0) (< gy (i32 HEIGHT))))
    (let index (select 0u (+ (* (+ (* (u32 gy) WIDTH) (u32 gx)) CHANNELS) c) inside))
    (return (vec2u index (select 0u 1u inside))))

(fn tile_origin ((wid vec3u) (nwg vec3u)) (-> vec2u)
    (let tile (+ (* (get wid y) (get nwg x)) (get wid x)))
    (return (vec2u (* (% tile TILES_X) 16u) (* (/ tile TILES_X) 16u))))

;; The column blur of quantity j of the blurred rows, at invocation t's
;; pixel of the tile.
(fn blurred_column ((t u32) (j u32)) (-> f32)
    (var sum 0.0)
    (for ((var q 0u) (< q 11u) (+= q 1u))
         (+= sum (* (at WEIGHTS q) (at rows (+ (* j BAND) (* (+ (/ t 16u) q) 16u) (% t 16u))))))
    (return sum))
