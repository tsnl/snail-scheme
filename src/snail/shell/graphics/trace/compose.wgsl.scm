;; The blended surfaces' layer over the first hits, once each is lit and
;; filtered: one triangle over the screen, drawn into the light the first
;; hits were filtered into, whose blend takes the layer's light by its
;; alpha, the albedo's, as alpha T + (1 - alpha) O. A pixel with no layer
;; has alpha 0, and keeps its light.
(var (@group 0) (@binding 0) (layer (texture_2d f32)))

(var (@group 0) (@binding 1) (albedo (texture_2d f32)))

(fn (@vertex) compose_vertex (((@builtin vertex_index) corner u32)) (-> (@builtin position) vec4f)
    (let unit (vec2f (f32 (bit-and corner 1u)) (f32 (>> corner 1u))))
    (return (vec4f (- (* unit 4.0) 1.0) 0.0 1.0)))

(fn (@fragment) compose_fragment (((@builtin position) position vec4f)) (-> (@location 0) vec4f)
    (let pixel (vec2i (get position xy)))
    (return (vec4f (get (textureLoad layer pixel 0) rgb) (get (textureLoad albedo pixel 0) a))))
