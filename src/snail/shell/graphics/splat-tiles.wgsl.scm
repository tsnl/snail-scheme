;; What binning gaussians into 16x16-pixel tiles shares, prepended to
;; splat-count, splat-keys and splat-ranges, after their constants from
;; (snail shell graphics splat-train): WIDTH, HEIGHT, TILES_X, TILES_Y,
;; COUNT gaussians and CAPACITY entries. A gaussian covers the tiles it
;; reaches: those with a pixel center where its alpha is at least 1/255,
;; the least the rasterizer blends, so binning drops nothing the
;; rasterizer would draw. A culled gaussian, of radius 0, covers none. To
;; splat-count and splat-keys a gaussian is the rasterizer's nine floats
;; (splat-forward): center x y, conic a b c, color r g b and opacity.

;; How far a gaussian of `opacity` reaches, as q(d) = a dx^2 + 2 b dx dy
;; + c dy^2 of its conic at offset d: alpha = opacity exp(-q / 2), with the
;; opacity as the rasterizer clamps it, is 1/255 where q = 2 ln(255
;; opacity), at most 3.33 standard deviations. Under alpha 1/255
;; everywhere, the reach is negative and no tile is reached.
(fn reach ((opacity f32)) (-> f32)
    (return (* 2.0 (log (* 255.0 (min opacity 0.99))))))

;; The tiles about a gaussian's reach, x0 y0 x1 y1, ends excluded: those
;; its bounding box touches, sqrt(limit s_xx) across and sqrt(limit s_yy)
;; down from its center, s being the screen covariance, the conic's
;; inverse.
(fn tile_rect ((center vec2f) (conic vec3f) (limit f32) (radius f32)) (-> vec4u)
    (if ((or (<= radius 0.0) (< limit 0.0)) (return (vec4u 0u))))
    (let det (- (* (get conic x) (get conic z)) (* (get conic y) (get conic y))))
    (let half (sqrt (/ (* limit (vec2f (get conic z) (get conic x))) det)))
    (let tiles (vec2f (f32 TILES_X) (f32 TILES_Y)))
    (let low (clamp (floor (/ (- center half) (f32 TILE))) (vec2f 0.0) tiles))
    (let high (clamp (ceil (/ (+ center half) (f32 TILE))) (vec2f 0.0) tiles))
    (return (vec4u (u32 (get low x)) (u32 (get low y)) (u32 (get high x)) (u32 (get high y)))))

(fn conic_power ((conic vec3f) (d vec2f)) (-> f32)
    (return (+ (* (get conic x) (get d x) (get d x))
               (* 2.0 (get conic y) (get d x) (get d y))
               (* (get conic z) (get d y) (get d y)))))

;; Whether a gaussian reaches tile (x, y): whether q is within `limit`
;; somewhere in the box of the tile's pixel centers. With the center
;; outside the box, q is least on the box's side nearest it across x or
;; on the one nearest it down y; along a side, q is a parabola, least
;; where its slope is zero, clamped to the side. With the center inside,
;; both sides are the center's own lines and q is 0.
(fn reaches ((center vec2f) (conic vec3f) (limit f32) (tile vec2u)) (-> bool)
    (let low (+ (* (vec2f tile) (f32 TILE)) 0.5))
    (let high (+ low (- (f32 TILE) 1.0)))
    (let near (- (clamp center low high) center))
    (let down (- (clamp (- (get center y) (/ (* (get conic y) (get near x)) (get conic z)))
                        (get low y)
                        (get high y))
                 (get center y)))
    (let across (- (clamp (- (get center x) (/ (* (get conic y) (get near y)) (get conic x)))
                          (get low x)
                          (get high x))
                   (get center x)))
    (return (<= (min (conic_power conic (vec2f (get near x) down))
                     (conic_power conic (vec2f across (get near y))))
                limit)))

;; A thread's index across rows of workgroups of 256.
(fn invocation ((gid vec3u) (nwg vec3u)) (-> u32)
    (return (+ (* (get gid y) (get nwg x) 256u) (get gid x))))
