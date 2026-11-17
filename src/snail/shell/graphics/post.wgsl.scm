;; From the frame's light to the screen, two full-screen triangles. Tone
;; mapping brings the light into range with the shoulder of Khronos's PBR
;; Neutral curve: a color whose largest channel is under `knee` passes
;; unchanged, and a brighter one is scaled down toward 1, keeping its hue,
;; and desaturated a little, as a bright light looks. FXAA then softens
;; the edges of what was drawn: it finds an edge's direction from the
;; brightness of the four diagonal neighbors and blends along it (Timothy
;; Lottes's FXAA, the reduced form many WebGL renderers use).
(var (@group 0) (@binding 0) (light (texture_2d f32)))

(var (@group 0) (@binding 1) (toned (texture_2d f32)))

(var (@group 0) (@binding 2) (bilinear sampler))

(const knee 0.8)

(const desaturation 0.15)

(fn (@vertex) post_vertex (((@builtin vertex_index) corner u32)) (-> (@builtin position) vec4f)
    (let unit (vec2f (f32 (bit-and corner 1u)) (f32 (>> corner 1u))))
    (return (vec4f (- (* unit 4.0) 1.0) 0.0 1.0)))

(fn shoulder ((color vec3f)) (-> vec3f)
    (let peak (max (get color r) (max (get color g) (get color b))))
    (if ((< peak knee) (return color)))
    (let room (- 1.0 knee))
    (let top (- 1.0 (/ (* room room) (- (+ peak room) knee))))
    (let fade (- 1.0 (/ 1.0 (+ (* desaturation (- peak top)) 1.0))))
    (return (mix (* color (/ top peak)) (vec3f top) fade)))

(fn (@fragment) tone_fragment (((@builtin position) position vec4f)) (-> (@location 0) vec4f)
    (let texel (textureLoad light (vec2i (get position xy)) 0))
    (return (vec4f (shoulder (get texel rgb)) 1.0)))

(fn luma ((color vec3f)) (-> f32)
    (return (dot color (vec3f 0.299 0.587 0.114))))

(fn tap ((place vec2f)) (-> vec3f)
    (return (get (textureSampleLevel toned bilinear place 0.0) rgb)))

(fn (@fragment) fxaa_fragment (((@builtin position) position vec4f)) (-> (@location 0) vec4f)
    (let texel (/ (vec2f 1.0) (vec2f (textureDimensions toned))))
    (let uv (* (get position xy) texel))
    (let m (luma (tap uv)))
    (let nw (luma (tap (+ uv (* (vec2f -1.0 -1.0) texel)))))
    (let ne (luma (tap (+ uv (* (vec2f 1.0 -1.0) texel)))))
    (let sw (luma (tap (+ uv (* (vec2f -1.0 1.0) texel)))))
    (let se (luma (tap (+ uv (* (vec2f 1.0 1.0) texel)))))
    (let low (min m (min (min nw ne) (min sw se))))
    (let high (max m (max (max nw ne) (max sw se))))
    (let edge (vec2f (- (+ sw se) (+ nw ne)) (- (+ nw sw) (+ ne se))))
    (let reduce (max (* (+ nw ne sw se) (/ 0.25 8.0)) (/ 1.0 128.0)))
    (let scale (/ 1.0 (+ (min (abs (get edge x)) (abs (get edge y))) reduce)))
    (let along (* (clamp (* edge scale) (vec2f -8.0) (vec2f 8.0)) texel))
    (let near (* 0.5 (+ (tap (- uv (* along (/ 1.0 6.0)))) (tap (+ uv (* along (/ 1.0 6.0)))))))
    (let far (+ (* near 0.5) (* 0.25 (+ (tap (- uv (* along 0.5))) (tap (+ uv (* along 0.5)))))))
    (let lf (luma far))
    (if ((or (< lf low) (> lf high)) (return (vec4f near 1.0))))
    (return (vec4f far 1.0)))
