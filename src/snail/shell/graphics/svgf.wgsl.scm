;; Spatiotemporal variance-guided filtering (Schied et al. 2017), as
;; enlighten filters its paths, over illumination: a pixel's radiance
;; with its first hit's emission taken out and its albedo divided out, so
;; the filters blur light, not texture, and `remodulate` puts both back.
;;
;;   temporal    the illumination reprojected through the G-buffer's
;;               motion from last frame's history, each of the four
;;               bilinear taps kept only where its previous depth and
;;               normal match, mixed with this frame's by 1 / (length + 1)
;;               but no less than `floor`; and the luminance's first and
;;               second moments the same way
;;   variance    the luminance's variance from the moments, or, while the
;;               history is shorter than four frames, from a 7x7
;;               neighborhood weighted by depth and normal
;;   atrous      one level of the edge-avoiding à-trous wavelet: a 5x5
;;               B-spline at `limits.z` pixels, weighted by depth, normal and
;;               luminance against the variance, which it carries forward
;;   remodulate  the filtered illumination times albedo, plus emission,
;;               into the light; the sky as traced; all scaled by the
;;               exposure, `limits.w` of the first slot
;;
;; The first level's output becomes the next frame's history. While the
;; camera holds still, `floor` is 0 and the history keeps growing, so a
;; still image converges as an average would.
(var (@group 0) (@binding 0) (noisy (texture_2d f32)))

(var (@group 0) (@binding 1) (albedo (texture_2d f32)))

(var (@group 0) (@binding 2) (emission (texture_2d f32)))

(var (@group 0) (@binding 3) (normals (texture_2d f32)))

(var (@group 0) (@binding 4) (depth texture_depth_2d))

(var (@group 0) (@binding 5) (motion (texture_2d f32)))

(var (@group 0) (@binding 6) (past_color (texture_2d f32)))

(var (@group 0) (@binding 7) (past_moments (texture_2d f32)))

(var (@group 0) (@binding 8) (past_place (texture_2d f32)))

(var (@group 0) (@binding 9) (integrated (texture_storage_2d rgba32float write)))

(var (@group 0) (@binding 10) (moments (texture_storage_2d rgba32float write)))

(var (@group 0) (@binding 11) (place (texture_storage_2d rgba32float write)))

(var (@group 0) (@binding 12) (source (texture_2d f32)))

(var (@group 0) (@binding 13) (filtered (texture_storage_2d rgba32float write)))

(var (@group 0) (@binding 14) (current_moments (texture_2d f32)))

(var (@group 0) (@binding 15) (light (texture_storage_2d rgba16float write)))

((var uniform) (@group 0) (@binding 16) (camera Camera3D))

((var uniform) (@group 0) (@binding 17) (filtering Filtering))

(var (@group 0) (@binding 18) (triangles (texture_2d u32)))

;; ---- Pixels ----

(fn inside ((id vec3u)) (-> bool)
    (let size (textureDimensions noisy))
    (return (and (< (get id x) (get size x)) (< (get id y) (get size y)))))

(fn unfolded ((e vec2f)) (-> vec3f)
    (var n (vec3f (get e x) (get e y) (- 1.0 (abs (get e x)) (abs (get e y)))))
    (let t (max (- (get n z)) 0.0))
    (+= (get n x) (select t (- t) (>= (get n x) 0.0)))
    (+= (get n y) (select t (- t) (>= (get n y) 0.0)))
    (return (normalize n)))

(fn normal_at ((p vec2i)) (-> vec3f)
    (return (unfolded (get (textureLoad normals p 0) xy))))

(fn sky_at ((p vec2i)) (-> bool)
    (return (>= (textureLoad depth p 0) 1.0)))

;; Where the pixel's surface is in the world.
(fn world_at ((p vec2i)) (-> vec3f)
    (let size (vec2f (textureDimensions depth)))
    (let ndc (- (* (/ (+ (vec2f p) 0.5) size) 2.0) 1.0))
    (let clip (*
               (get camera inverse)
               (vec4f (get ndc x) (- (get ndc y)) (textureLoad depth p 0) 1.0)))
    (return (/ (get clip xyz) (get clip w))))

(fn luminance ((c vec3f)) (-> f32)
    (return (dot c (vec3f 0.2126 0.7152 0.0722))))

;; The albedo light is divided by, kept from zero so dark surfaces still
;; carry their light.
(fn demodulator ((p vec2i)) (-> vec3f)
    (return (max (get (textureLoad albedo p 0) xyz) (vec3f 0.03))))

;; ---- Temporal ----

(fn (@compute) (@workgroup_size 8 8) temporal (((@builtin global_invocation_id) id vec3u))
    (if ((not (inside id)) (return)))
    (let p (vec2i (get id xy)))
    (if ((sky_at p)
         (textureStore integrated p (vec4f 0.0))
         (textureStore moments p (vec4f 0.0))
         (textureStore place p (vec4f 0.0))
         (return)))
    (let radiance (textureLoad noisy p 0))
    ;; A negative alpha holds this still pixel's previous observation.
    (if ((< (get radiance w) 0.0)
         (textureStore integrated p (textureLoad past_color p 0))
         (textureStore moments p (textureLoad past_moments p 0))
         (textureStore place p (textureLoad past_place p 0))
         (return)))
    (let sample (/
                 (max (- (get radiance xyz) (get (textureLoad emission p 0) xyz)) (vec3f 0.0))
                 (demodulator p)))
    (let world (world_at p))
    (let normal (normal_at p))
    (let size (vec2f (textureDimensions noisy)))
    (let before (- (- (+ (vec2f p) 0.5) (* (get (textureLoad motion p 0) xy) size)) 0.5))
    (let base (vec2i (floor before)))
    (let f (fract before))
    (var color (vec3f 0.0))
    (var moment (vec2f 0.0))
    (var ages 0.0)
    (var total 0.0)
    ;; The rasterizer projects the *previous pose* of a moving triangle.
    ;; Comparing its current world position would discard its own history.
    (let key (f32 (+ 1u (get (textureLoad triangles p 0) x))))
    (let previous_z (get (textureLoad emission p 0) w))
    (let tolerance (* 0.02 (max 0.001 (abs previous_z))))
    (for ((var k 0) (< k 4) (+= k 1))
         (let offset (vec2i (bit-and k 1) (>> k 1)))
         (let q (+ base offset))
         (if ((or (any (< q (vec2i 0))) (any (>= q (vec2i size)))) (continue)))
         (let was (textureLoad past_place q 0))
         (if ((or (!= (get was w) key) (> (abs (- (get was x) previous_z)) tolerance)) (continue)))
         (if ((< (dot (unfolded (get was yz)) normal) 0.9)
              (continue)))
         (let w (* (select (- 1.0 (get f x)) (get f x) (== (get offset x) 1))
                   (select (- 1.0 (get f y)) (get f y) (== (get offset y) 1))))
         (+= color (* (get (textureLoad past_color q 0) xyz) w))
         (let m (textureLoad past_moments q 0))
         (+= moment (* (get m xy) w))
         (+= ages (* (get m z) w))
         (+= total w))
    (let l (luminance sample))
    (var history 0.0)
    (if ((> total 0.001)
         (/= color total)
         (/= moment total)
         (= history (min (+ (round (/ ages total)) 1.0) (get filtering limits x)))))
    ;; Compare the old illumination with fresh observations on this surface.
    ;; The moving shadow or headlamp on a stationary road has zero velocity.
    (if ((and (> history 1.0) (> (get filtering limits y) 0.0))
         (var low l) (var high l)
         (let neighbors (array (vec2i -1 0) (vec2i 1 0) (vec2i 0 -1) (vec2i 0 1)))
         (for ((var k 0) (< k 4) (+= k 1))
              (let q (clamp (+ p (at neighbors k)) (vec2i 0) (- (vec2i size) 1)))
              (if ((!= (get (textureLoad triangles q 0) x) (get (textureLoad triangles p 0) x))
                   (continue)))
              (let obs (textureLoad noisy q 0))
              (if ((< (get obs w) 0.0) (continue)))
              (let lum (luminance
                        (/ (max (- (get obs xyz) (get (textureLoad emission q 0) xyz)) (vec3f 0.0))
                           (demodulator q))))
              (= low (min low lum)) (= high (max high lum)))
         (let old (luminance color)) (let pad (+ 0.025 (* 0.20 high)))
         (if ((or (< old (- low pad)) (> old (+ high pad)))
              (= history (min history 2.0))
              (*= color (/ (clamp old (max 0.0 (- low pad)) (+ high pad)) (max old 1e-6)))))))
    (let alpha (select
                (max (/ 1.0 (max history 1.0)) (get filtering limits y))
                1.0
                (<= history 1.0)))
    (let mixed (mix color sample alpha))
    (let mixed_moment (mix moment (vec2f l (* l l)) alpha))
    (textureStore integrated p (vec4f mixed 0.0))
    (textureStore moments p (vec4f mixed_moment (max history 1.0) 0.0))
    (textureStore place
                  p
                  (vec4f (get (* (get camera view_projection) (vec4f world 1.0)) z)
                         (get (textureLoad normals p 0) xy) key)))

;; ---- Variance ----

;; How much a neighbor at `q` counts toward `p`'s: by depth and normal.
(fn geometric_weight ((world vec3f) (normal vec3f) (q vec2i) (scale f32)) (-> f32)
    (if ((sky_at q) (return 0.0)))
    (let d (distance (world_at q) world))
    (let n (pow (max 0.0 (dot (normal_at q) normal)) 64.0))
    (return (* n (exp (- (/ d scale))))))

(fn (@compute) (@workgroup_size 8 8) variance (((@builtin global_invocation_id) id vec3u))
    (if ((not (inside id)) (return)))
    (let p (vec2i (get id xy)))
    (let center (textureLoad source p 0))
    (if ((sky_at p) (textureStore filtered p (vec4f 0.0)) (return)))
    (let m (textureLoad current_moments p 0))
    (if ((>= (get m z) 4.0)
         (textureStore filtered
                       p
                       (vec4f (get center xyz) (max 0.0 (- (get m y) (* (get m x) (get m x))))))
         (return)))
    (let world (world_at p))
    (let normal (normal_at p))
    (let scale (* 0.05 (max 1.0 (distance world (get camera eye xyz)))))
    (var color (vec3f 0.0))
    (var moment (vec2f 0.0))
    (var total 0.0)
    (let size (vec2i (textureDimensions noisy)))
    (for ((var y -3) (<= y 3) (+= y 1))
         (for ((var x -3) (<= x 3) (+= x 1))
              (let q (+ p (vec2i x y)))
              (if ((or (any (< q (vec2i 0))) (any (>= q size))) (continue)))
              (let w (geometric_weight world normal q scale))
              (+= color (* (get (textureLoad source q 0) xyz) w))
              (+= moment (* (get (textureLoad current_moments q 0) xy) w))
              (+= total w)))
    (let t (max total 1e-6))
    (let mo (/ moment t))
    (textureStore filtered
                  p
                  (vec4f (/ color t)
                         (* (max 0.0 (- (get mo y) (* (get mo x) (get mo x)))) (/ 4.0 (get m z))))))

;; ---- À-trous ----

(fn (@compute) (@workgroup_size 8 8) atrous (((@builtin global_invocation_id) id vec3u))
    (if ((not (inside id)) (return)))
    (let p (vec2i (get id xy)))
    (let center (textureLoad source p 0))
    (if ((sky_at p) (textureStore filtered p center) (return)))
    (let stride (i32 (get filtering limits z)))
    (let world (world_at p))
    (let normal (normal_at p))
    (let scale (* 0.05 (max 1.0 (distance world (get camera eye xyz))) (f32 stride)))
    (let l (luminance (get center xyz)))
    (let deviation (* 4.0 (sqrt (max (get center w) 1e-8))))
    (let size (vec2i (textureDimensions noisy)))
    (var (kernel (array f32 3)) (array 0.375 0.25 0.0625))
    (var color (vec3f 0.0))
    (var spread 0.0)
    (var total 0.0)
    (for ((var y -2) (<= y 2) (+= y 1))
         (for ((var x -2) (<= x 2) (+= x 1))
              (let q (+ p (* (vec2i x y) stride)))
              (if ((or (any (< q (vec2i 0))) (any (>= q size))) (continue)))
              (let neighbor (textureLoad source q 0))
              (let lw (exp (- (/ (abs (- (luminance (get neighbor xyz)) l)) (+ deviation 1e-6)))))
              (let w (*
                      (at kernel (abs x))
                      (at kernel (abs y))
                      lw
                      (geometric_weight world normal q scale)))
              (+= color (* (get neighbor xyz) w))
              (+= spread (* (get neighbor w) w w))
              (+= total w)))
    (let t (max total 1e-6))
    (textureStore filtered p (vec4f (/ color t) (/ spread (* t t)))))

;; ---- Light ----

(fn (@compute) (@workgroup_size 8 8) remodulate (((@builtin global_invocation_id) id vec3u))
    (if ((not (inside id)) (return)))
    (let p (vec2i (get id xy)))
    (let exposure (get filtering limits w))
    (if ((sky_at p)
         (textureStore light p (vec4f (* (get (textureLoad noisy p 0) xyz) exposure) 1.0))
         (return)))
    (let illumination (get (textureLoad source p 0) xyz))
    (textureStore light
                  p
                  (vec4f
                   (* (+ (* illumination (demodulator p)) (get (textureLoad emission p 0) xyz))
                      exposure)
                   1.0)))
