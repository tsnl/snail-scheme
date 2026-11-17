;; Composing a picture into an atlas page: each piece copies a region of a
;; source image texel for texel to its place on the page, its colors
;; swapped by a run of the swap table, over what is already there. A piece
;; covers `clip`, its rectangle in the page's clip space; the source texel
;; under a page pixel is the pixel's position plus `offset`.
(var (@group 0) (@binding 0) (source (texture_2d f32)))

((var storage read) (@group 0) (@binding 1) (swaps (array vec2i)))

(struct PieceOut
        ((@builtin position) position vec4f)
        ((@location 0) (@interpolate flat) offset vec2f)
        ((@location 1) (@interpolate flat) run vec2i))

(fn (@vertex)
    piece_vertex
    (((@builtin vertex_index) corner u32)
     ((@location 0) clip vec4f)
     ((@location 1) offset vec2f)
     ((@location 2) run vec2i))
    (-> PieceOut)
    (let unit (vec2f (f32 (bit-and corner 1u)) (f32 (bit-and (>> corner 1u) 1u))))
    (var (out PieceOut))
    (= (get out position) (vec4f (mix (get clip xy) (get clip zw) unit) 0.0 1.0))
    (= (get out offset) offset)
    (= (get out run) run)
    (return out))

;; A color is 0xRRGGBB; a swap is (from, to).
(fn (@fragment) piece_fragment ((in PieceOut)) (-> (@location 0) vec4f)
    (let texel (textureLoad source (vec2i (floor (+ (get in position xy) (get in offset)))) 0))
    (let rgb (vec3i (round (* (get texel rgb) 255.0))))
    (let key (bit-or (<< (get rgb x) 16) (<< (get rgb y) 8) (get rgb z)))
    (var color texel)
    (for ((var i (get in run x)) (< i (+ (get in run x) (get in run y))) (+= i 1))
         (if ((== (get (at swaps i) x) key)
              (let to (get (at swaps i) y))
              (= color
                 (vec4f (/ (vec3f (f32 (bit-and (>> to 16) 255))
                                  (f32 (bit-and (>> to 8) 255))
                                  (f32 (bit-and to 255)))
                           255.0)
                        (get texel a)))
              (break))))
    (return color))
