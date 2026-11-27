;; Quads in world units under a 2D camera, each a region of one page of a
;; texture array, tinted. A quad's corners are snapped to the target's
;; pixels, so pixel art stays crisp at any camera position. Up is +y; a
;; region's texels run down from its top.
((var uniform) (@group 0) (@binding 0) (view SpriteView))

(var (@group 0) (@binding 1) (pages (texture_2d_array f32)))

(var (@group 0) (@binding 2) (nearest sampler))

(struct QuadOut
        ((@builtin position) position vec4f)
        ((@location 0) texel vec2f)
        ((@location 1) (@interpolate flat) page i32)
        ((@location 2) color vec4f))

(fn (@vertex)
    quad_vertex
    (((@builtin vertex_index) corner u32)
     ((@location 0) center vec2f)
     ((@location 1) size vec2f)
     ((@location 2) angle f32)
     ((@location 3) page i32)
     ((@location 4) region vec4f)
     ((@location 5) color vec4f))
    (-> QuadOut)
    (let unit (vec2f (f32 (bit-and corner 1u)) (f32 (bit-and (>> corner 1u) 1u))))
    (let local (* (- unit 0.5) size))
    (let c (cos angle))
    (let s (sin angle))
    (let world (+
                center
                (vec2f (- (* c (get local x)) (* s (get local y)))
                       (+ (* s (get local x)) (* c (get local y))))))
    (let clip (* (get view projection) (vec4f world 0.0 1.0)))
    (let pixels (get view pixels))
    (let pixel (round (* (+ (* (/ (get clip xy) (get clip w)) 0.5) 0.5) pixels)))
    (var (out QuadOut))
    (= (get out position) (vec4f (* (- (* (/ pixel pixels) 2.0) 1.0) (get clip w)) (get clip zw)))
    (= (get out texel)
       (+ (get region xy) (* (vec2f (get unit x) (- 1.0 (get unit y))) (get region zw))))
    (= (get out page) page)
    (= (get out color) color)
    (return out))

(fn (@fragment) quad_fragment ((in QuadOut)) (-> (@location 0) vec4f)
    (let size (vec2f (get (textureDimensions pages) xy)))
    (let color (*
                (textureSample pages nearest (/ (get in texel) size) (get in page))
                (get in color)))
    (if ((< (get color a) 0.004) (discard)))
    (return color))
