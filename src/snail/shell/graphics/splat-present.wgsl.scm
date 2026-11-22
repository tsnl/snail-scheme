;; An image the training renderer blended, onto the target: one triangle
;; covers it, and each fragment reads its pixel's three floats, row-major
;; as the blend wrote them. WIDTH comes before this file.
((var storage read) (@group 0) (@binding 0) (image (array f32)))

(fn (@vertex) present_vertex (((@builtin vertex_index) corner u32)) (-> (@builtin position) vec4f)
    (let unit (vec2f (f32 (bit-and corner 1u)) (f32 (>> corner 1u))))
    (return (vec4f (- (* unit 4.0) 1.0) 0.0 1.0)))

(fn (@fragment) present_fragment (((@builtin position) position vec4f)) (-> (@location 0) vec4f)
    (let p (* 3u (+ (* (u32 (get position y)) WIDTH) (u32 (get position x)))))
    (return (vec4f (at image p) (at image (+ p 1u)) (at image (+ p 2u)) 1.0)))
