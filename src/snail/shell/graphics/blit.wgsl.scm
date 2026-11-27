;; A normalized, top-left-origin sampled copy into the output attachment.
(var (@group 0) (@binding 0) (source (texture_2d f32)))

(var (@group 0) (@binding 1) (bilinear sampler))

(struct Corner
        ((@builtin position) position vec4f)
        ((@location 0) uv vec2f))

(fn (@vertex) blit_vertex (((@builtin vertex_index) corner u32)) (-> Corner)
    (let unit (vec2f (f32 (bit-and corner 1u)) (f32 (>> corner 1u))))
    (var (out Corner))
    (= (get out position) (vec4f (- (* unit 4.0) 1.0) 0.0 1.0))
    (= (get out uv) (vec2f (* (get unit x) 2.0) (- 1.0 (* (get unit y) 2.0))))
    (return out))

(fn (@fragment) blit_fragment ((in Corner)) (-> (@location 0) vec4f)
    (return (textureSampleLevel source bilinear (get in uv) 0.0)))
