;; One triangle covering the target, filled with the uniform's color.
((var uniform) (@group 0) (@binding 0) (paint Paint_uniform))

(fn (@vertex) vertex_main (((@builtin vertex_index) i u32)) (-> (@builtin position) vec4f)
    (let corners ((array vec2f 3) (vec2f -1.0 -3.0) (vec2f 3.0 1.0) (vec2f -1.0 1.0)))
    (return (vec4f (at corners i) 0.0 1.0)))

(fn (@fragment) fragment_main () (-> (@location 0) vec4f)
    (return (get paint color)))
