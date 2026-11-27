;; Scene-linear HDR is tone-mapped in compute, then FXAA filters the display image.
(var (@group 0) (@binding 0) (light (texture_2d f32)))

(var (@group 0) (@binding 1) (toned (texture_2d f32)))

(var (@group 0) (@binding 2) (bilinear sampler))

(struct ScreenPoint ((@builtin position) position vec4f) ((@location 0) uv vec2f))

(fn (@vertex) post_vertex (((@builtin vertex_index) corner u32)) (-> ScreenPoint)
    (let unit (vec2f (f32 (bit-and corner 1u)) (f32 (>> corner 1u))))
    (return (ScreenPoint (vec4f (- (* unit 4.0) 1.0) 0.0 1.0)
                         (vec2f (* 2.0 (get unit x)) (- 1.0 (* 2.0 (get unit y)))))))

(var (@group 0) (@binding 3) (mapped (texture_storage_2d rgba8unorm write)))

(fn map_texel ((p vec2u) (curve u32))
    (if ((any (>= p (textureDimensions mapped))) (return)))
    (textureStore mapped p (vec4f (tone_mapped curve (get (textureLoad light p 0) rgb)) 1.0)))

(fn (@compute) (@workgroup_size 8 8) tone_neutral (((@builtin global_invocation_id) p vec3u))
    (map_texel (get p xy) 0u))
(fn (@compute) (@workgroup_size 8 8) tone_filmic (((@builtin global_invocation_id) p vec3u))
    (map_texel (get p xy) 1u))
(fn (@compute) (@workgroup_size 8 8) tone_photographic (((@builtin global_invocation_id) p vec3u))
    (map_texel (get p xy) 2u))

(fn luma ((color vec3f)) (-> f32)
    (return (dot color (vec3f 0.299 0.587 0.114))))

(fn tap ((place vec2f)) (-> vec3f)
    (return (get (textureSampleLevel toned bilinear place 0.0) rgb)))

(fn (@fragment) fxaa_fragment (((@location 0) uv vec2f)) (-> (@location 0) vec4f)
    (let texel (/ (vec2f 1.0) (vec2f (textureDimensions toned))))
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
