;; What binning gaussians into 16x16-pixel tiles shares, prepended to
;; splat-count, splat-keys and splat-ranges, after their constants from
;; (snail shell graphics splat-train): WIDTH, HEIGHT, TILES_X, TILES_Y,
;; COUNT gaussians and CAPACITY entries. A gaussian covers the tiles its
;; square of `radius` pixels around its center touches; radius 0 covers
;; none.

;; The tiles a gaussian covers, x0 y0 x1 y1, ends excluded.
(fn tile_rect ((center vec2f) (radius f32)) (-> vec4u)
    (let limit (vec2f (f32 TILES_X) (f32 TILES_Y)))
    (let low (clamp (floor (/ (- center radius) 16.0)) (vec2f 0.0) limit))
    (let high (clamp (ceil (/ (+ center radius) 16.0)) (vec2f 0.0) limit))
    (if ((<= radius 0.0) (return (vec4u 0u))))
    (return (vec4u (u32 (get low x)) (u32 (get low y)) (u32 (get high x)) (u32 (get high y)))))

(fn rect_area ((rect vec4u)) (-> u32)
    (return (* (- (get rect z) (get rect x)) (- (get rect w) (get rect y)))))

;; A thread's index across rows of workgroups of 256.
(fn invocation ((gid vec3u) (nwg vec3u)) (-> u32)
    (return (+ (* (get gid y) (get nwg x) 256u) (get gid x))))
