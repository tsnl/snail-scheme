;; Lighting the G-buffer under the sun, a full-screen triangle: each pixel
;; with a surface is lit where its depth puts it, and a pixel without one is
;; left as it was. `Camera3D`, `Sun` and `lit` come from Pod and
;; lighting.wgsl.scm.
((var uniform) (@group 0) (@binding 0) (camera Camera3D))

((var uniform) (@group 0) (@binding 1) (sun Sun))

(var (@group 0) (@binding 2) (albedo (texture_2d f32)))

(var (@group 0) (@binding 3) (normals (texture_2d f32)))

(var (@group 0) (@binding 4) (materials (texture_2d f32)))

(var (@group 0) (@binding 5) (depths texture_depth_2d))

(fn (@vertex)
    sun_vertex
    (((@builtin vertex_index) corner u32))
    (-> (@builtin position) vec4f)
    (let unit (vec2f (f32 (bit-and corner 1u)) (f32 (>> corner 1u))))
    (return (vec4f (- (* unit 4.0) 1.0) 0.0 1.0)))

(fn (@fragment) sun_fragment (((@builtin position) position vec4f)) (-> (@location 0) vec4f)
    (let pixel (vec2i (get position xy)))
    (let depth (textureLoad depths pixel 0))
    (if ((>= depth 1.0) (discard)))
    (let size (vec2f (textureDimensions depths)))
    (let ndc (vec2f (- (* (/ (get position x) (get size x)) 2.0) 1.0)
                    (- 1.0 (* (/ (get position y) (get size y)) 2.0))))
    (let point (* (get camera inverse) (vec4f ndc depth 1.0)))
    (let world (/ (get point xyz) (get point w)))
    (let view (select (normalize (- (get camera eye xyz) world))
                      (- (normalize (get camera forward xyz)))
                      (> (get camera eye w) 0.5)))
    (let material (textureLoad materials pixel 0))
    (return (vec4f (lit (get (textureLoad albedo pixel 0) rgb)
                        (get (textureLoad normals pixel 0) xyz)
                        view
                        (get material x)
                        (get material y)
                        (get material z)
                        sun)
                   1.0)))
