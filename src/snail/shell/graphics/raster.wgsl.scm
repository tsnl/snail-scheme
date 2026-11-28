;; Rasterizing mesh instances lit at once by the sun: one vertex stage and
;; one fragment stage, for opaque surfaces and for translucent ones blended
;; over what is drawn. `Camera3D`, `Style`, `Sun` and `lit` come from Pod
;; and lighting.wgsl.scm.
;;
;; An instance moves from where it was, `before` (Instance's `from`), to
;; `place` as the camera's motion goes from 0 to 1, turns by its yaw,
;; `place.w`, and, when `before.w` is 1, turns to
;; face the camera as an upright sprite does. Its scale's w is its glow, and
;; its material is metalness then roughness.
((var uniform) (@group 0) (@binding 0) (camera Camera3D))

((var uniform) (@group 1) (@binding 0) (style Style))

((var uniform) (@group 2) (@binding 0) (sun Sun))

(struct Surface
        ((@builtin position) position vec4f)
        ((@location 0) color vec3f)
        ((@location 1) normal vec3f)
        ((@location 2) world vec3f)
        ((@location 3) material vec3f))

;; The horizontal direction toward the camera, or +z when looking vertically.
(fn toward_camera ((forward vec2f)) (-> vec2f)
    (if ((== (dot forward forward) 0.0) (return (vec2f 0.0 1.0))))
    (return (normalize (- forward))))

;; Rotate about y given the x and z components of the new +z direction.
(fn turn_y ((v vec3f) (heading vec2f)) (-> vec3f)
    (return (vec3f (+ (* (get heading y) (get v x)) (* (get heading x) (get v z)))
                   (get v y)
                   (- (* (get heading y) (get v z)) (* (get heading x) (get v x))))))

(fn (@vertex)
    surface_vertex
    (((@location 0) position vec3f)
     ((@location 1) normal vec3f)
     ((@location 2) uv vec2f)
     ((@location 3) place vec4f)
     ((@location 4) scale vec4f)
     ((@location 5) color vec4f)
     ((@location 6) before vec4f)
     ((@location 7) material vec2f))
    (-> Surface)
    (let yaw (vec2f (sin (get place w)) (cos (get place w))))
    (let p (turn_y (* position (get scale xyz)) yaw))
    (var offset p)
    (var world_normal (turn_y (/ normal (get scale xyz)) yaw))
    (if ((> (get before w) 0.5)
         (let back (toward_camera (get camera forward xz)))
         (= offset (turn_y p back))
         (= world_normal (vec3f (get back x) 0.0 (get back y)))))
    (let world (+ offset (mix (get before xyz) (get place xyz) (get camera forward w))))
    (var (out Surface))
    (= (get out position) (* (get camera view_projection) (vec4f world 1.0)))
    (= (get out normal) world_normal)
    (= (get out color) (get color rgb))
    (= (get out world) world)
    (= (get out material) (vec3f (get material x) (get material y) (get scale w)))
    (return out))

;; A revealed batch shows only within its disc on the ground.
(fn hidden ((world vec3f)) (-> bool)
    (return (and (>= (get style radius) 0.0)
                 (> (distance (get world xz) (vec2f (get style center_x) (get style center_z)))
                    (get style radius)))))

;; The direction toward the eye: the same everywhere for an orthographic
;; camera, whose eye's w is 1.
(fn toward_eye ((world vec3f)) (-> vec3f)
    (return (select (normalize (- (get camera eye xyz) world))
                    (- (normalize (get camera forward xyz)))
                    (> (get camera eye w) 0.5))))

(fn (@fragment) forward_fragment ((in Surface)) (-> (@location 0) vec4f)
    (if ((hidden (get in world)) (discard)))
    (let color (lit (get in color)
                    (get in normal)
                    (toward_eye (get in world))
                    (get in material x)
                    (get in material y)
                    (get in material z)
                    sun))
    (return (vec4f color (get style opacity))))
