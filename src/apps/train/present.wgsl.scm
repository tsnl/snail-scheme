;; The image training last drew, a row-major RGB float buffer, fitted into
;; the canvas with its aspect kept and black around it: a triangle over
;; the canvas whose fragments read the image's nearest pixel.
((var uniform) (@group 0) (@binding 0) (sizes vec4f))

((var storage read) (@group 0) (@binding 1) (image (array f32)))

(fn (@vertex) present_vertex (((@builtin vertex_index) i u32)) (-> (@builtin position) vec4f)
    (let corner (vec2f (f32 (bit-and (<< i 1u) 2u)) (f32 (bit-and i 2u))))
    (return (vec4f (- (* corner 2.0) 1.0) 0.0 1.0)))

(fn (@fragment) present_fragment (((@builtin position) fragment vec4f)) (-> (@location 0) vec4f)
    (let canvas (get sizes xy))
    (let pixels (get sizes zw))
    (let scale (min (/ (get canvas x) (get pixels x)) (/ (get canvas y) (get pixels y))))
    (let p (/ (- (get fragment xy) (* 0.5 (- canvas (* scale pixels)))) scale))
    (if ((or (any (< p (vec2f 0.0))) (any (>= p pixels))) (return (vec4f 0.0 0.0 0.0 1.0))))
    (let k (* 3u (+ (* (u32 (get p y)) (u32 (get pixels x))) (u32 (get p x)))))
    (let color (vec3f (at image k) (at image (+ k 1u)) (at image (+ k 2u))))
    (return (vec4f (clamp color (vec3f 0.0) (vec3f 1.0)) 1.0)))
