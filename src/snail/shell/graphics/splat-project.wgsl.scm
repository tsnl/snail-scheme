;; Projecting 3D gaussians to the screen, an invocation a gaussian, as
;; Kerbl et al.'s 3D Gaussian Splatting does: each gaussian is placed by
;; its row of the transforms table, its covariance R S S^T R^T carried
;; through that transform and the view and linearized through the pinhole
;; at its center (EWA splatting), blurred by 0.3 pixels^2 so it covers at
;; least a pixel, and inverted to the conic the fragment stage evaluates.
;; Its color is its spherical harmonics seen from the eye, in its own
;; frame. Its sort key orders far before near: the depth's bits, which
;; order as positive floats do, inverted. A gaussian that is culled keeps
;; radius 0, which draws nothing, and the largest key.
;;
;; Screen positions are pixels from the target's center, up being +y; the
;; view looks down -z. `Gaussian`, `SplatCamera` and `Projected` come from
;; Pod.
((var uniform) (@group 0) (@binding 0) (camera SplatCamera))

((var storage read) (@group 0) (@binding 1) (gaussians (array Gaussian)))

((var storage read) (@group 0) (@binding 2) (harmonics (array f32)))

((var storage read) (@group 0) (@binding 3) (transforms (array mat4x4f)))

((var storage read_write) (@group 0) (@binding 4) (projected (array Projected)))

((var storage read_write) (@group 0) (@binding 5) (keys (array u32)))

((var storage read_write) (@group 0) (@binding 6) (values (array u32)))

(fn linear ((m mat4x4f)) (-> mat3x3f)
    (return (mat3x3f (get (at m 0) xyz) (get (at m 1) xyz) (get (at m 2) xyz))))

;; A unit quaternion x, y, z, w as a rotation, column by column.
(fn rotation ((q vec4f)) (-> mat3x3f)
    (let x (get q x))
    (let y (get q y))
    (let z (get q z))
    (let w (get q w))
    (return (mat3x3f (- 1.0 (* 2.0 (+ (* y y) (* z z))))
                     (* 2.0 (+ (* x y) (* w z)))
                     (* 2.0 (- (* x z) (* w y)))
                     (* 2.0 (- (* x y) (* w z)))
                     (- 1.0 (* 2.0 (+ (* x x) (* z z))))
                     (* 2.0 (+ (* y z) (* w x)))
                     (* 2.0 (+ (* x z) (* w y)))
                     (* 2.0 (- (* y z) (* w x)))
                     (- 1.0 (* 2.0 (+ (* x x) (* y y)))))))

;; A direction in the world, in the frame a transform's linear part maps
;; from: its inverse, as the transposed cofactors, scaled by any positive
;; number, which normalizing removes.
(fn unmapped ((a mat3x3f) (direction vec3f)) (-> vec3f)
    (let cofactors (mat3x3f
                    (cross (at a 1) (at a 2))
                    (cross (at a 2) (at a 0))
                    (cross (at a 0) (at a 1))))
    (let sign (select 1.0 -1.0 (< (dot (at a 0) (at cofactors 0)) 0.0)))
    (return (normalize (* sign (* (transpose cofactors) direction)))))

;; The screen-space covariance of a gaussian whose linear map from the unit
;; sphere to the view is `m`, centered at `view` at depth z: J m (J m)^T,
;; with J the pinhole's Jacobian there, its tangents clamped to 1.3 times
;; the field of view as the reference does, and the blur added.
(fn screen_covariance ((m mat3x3f) (view vec3f) (z f32)) (-> mat2x2f)
    (let focal (get camera focal))
    (let limit (* 1.3 (/ (* 0.5 (get camera viewport)) focal)))
    (let tangent (clamp (/ (get view xy) z) (- limit) limit))
    (let j (mat3x2f (/ (get focal x) z)
                    0.0
                    0.0
                    (/ (get focal y) z)
                    (/ (* (get focal x) (get tangent x)) z)
                    (/ (* (get focal y) (get tangent y)) z)))
    (let t (* j m))
    (return (+ (* t (transpose t)) (mat2x2f 0.3 0.0 0.0 0.3))))

(fn (@compute) (@workgroup_size 256) project (((@builtin global_invocation_id) id vec3u))
    (let i (get id x))
    (if ((>= i (arrayLength (address-of gaussians))) (return)))
    (= (at values i) i)
    (= (at keys i) 4294967295u)
    (= (get (at projected i) radius) 0.0)
    (let g (at gaussians i))
    (if ((< (get g opacity) (/ 1.0 255.0)) (return)))
    (let model (at transforms (get g transform)))
    (let world (* model (vec4f (get g position) 1.0)))
    (let view (get (* (get camera view) world) xyz))
    (let z (- (get view z)))
    (if ((< z 0.2) (return)))
    (let center (/ (* (get camera focal) (get view xy)) z))
    (if ((any (> (abs center) (* 0.65 (get camera viewport)))) (return)))
    (let a (linear model))
    (let local (*
                (rotation (get g rotation))
                (mat3x3f (get g scale x) 0.0 0.0 0.0 (get g scale y) 0.0 0.0 0.0 (get g scale z))))
    (let spread (screen_covariance (* (linear (get camera view)) a local) view z))
    (let det (-
              (* (at (at spread 0) 0) (at (at spread 1) 1))
              (* (at (at spread 0) 1) (at (at spread 0) 1))))
    (if ((<= det 0.0) (return)))
    (let mid (* 0.5 (+ (at (at spread 0) 0) (at (at spread 1) 1))))
    (let largest (+ mid (sqrt (max 0.1 (- (* mid mid) det)))))
    (let toward (unmapped a (normalize (- (get world xyz) (get camera eye xyz)))))
    (= (at projected i)
       (Projected (vec4f (/ (at (at spread 1) 1) det)
                         (/ (- (at (at spread 0) 1)) det)
                         (/ (at (at spread 0) 0) det)
                         0.0)
                  (vec4f (shade i toward) (get g opacity))
                  center
                  (ceil (* 3.0 (sqrt largest)))))
    (= (at keys i) (bit-not ((bitcast u32) z))))
