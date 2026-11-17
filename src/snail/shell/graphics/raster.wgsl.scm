;; Rasterizing mesh instances: one vertex stage, and two fragment stages,
;; one writing the G-buffer and one lighting a translucent surface at once
;; over what is drawn. `Camera3D`, `Style`, `Sun` and `lit` come from Pod and
;; lighting.wgsl.scm.
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

(fn (@vertex)
    surface_vertex
    (((@location 0) position vec3f)
     ((@location 1) normal vec3f)
     ((@location 2) uv vec2f)
     ((@location 3) place vec4f)
     ((@location 4) scale vec4f)
     ((@location 5) color vec4f)
     ((@location 6) before vec4f)
     ((@location 7) material vec4f))
    (-> Surface)
    (let back (normalize (+ (- (get camera forward xz)) (vec2f 0.0 1e-6))))
    (let upright (> (get before w) 0.5))
    (let yaw (+ (get place w) (select 0.0 (atan2 (get back x) (get back y)) upright)))
    (let c (cos yaw))
    (let s (sin yaw))
    (let p (* position (get scale xyz)))
    (let n (/ normal (get scale xyz)))
    (let origin (mix (get before xyz) (get place xyz) (get camera forward w)))
    (let world (+ (vec3f (+ (* c (get p x)) (* s (get p z)))
                         (get p y)
                         (- (* c (get p z)) (* s (get p x))))
                  origin))
    (var (out Surface))
    (= (get out position) (* (get camera view_projection) (vec4f world 1.0)))
    (= (get out normal)
       (select
        (vec3f (+ (* c (get n x)) (* s (get n z))) (get n y) (- (* c (get n z)) (* s (get n x))))
        (vec3f (get back x) 0.0 (get back y))
        upright))
    (= (get out color) (get color rgb))
    (= (get out world) world)
    (= (get out material) (vec3f (get material x) (get material y) (get scale w)))
    (return out))

;; A revealed batch shows only within its disc on the ground.
(fn hidden ((world vec3f)) (-> bool)
    (return (and (>= (get style radius) 0.0)
                 (> (distance (get world xz) (vec2f (get style center_x) (get style center_z)))
                    (get style radius)))))

(struct GBuffer
        ((@location 0) albedo vec4f)
        ((@location 1) normal vec4f)
        ((@location 2) material vec4f))

(fn (@fragment) gbuffer_fragment ((in Surface)) (-> GBuffer)
    (if ((hidden (get in world)) (discard)))
    (var (out GBuffer))
    (= (get out albedo) (vec4f (get in color) 1.0))
    (= (get out normal) (vec4f (normalize (get in normal)) 0.0))
    (= (get out material) (vec4f (get in material) 1.0))
    (return out))

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
