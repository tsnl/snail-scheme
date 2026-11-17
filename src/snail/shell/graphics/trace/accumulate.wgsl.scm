;; While the camera holds still, each frame's paths are averaged with
;; those before: `frames` is how many the history holds, 0 when the
;; camera has moved, so the history restarts. The average goes to the
;; next history and to the light that post-processing reads.
(var (@group 0) (@binding 0) (noisy (texture_2d f32)))

(var (@group 0) (@binding 1) (history (texture_2d f32)))

(var (@group 0) (@binding 2) (next (texture_storage_2d rgba16float write)))

(var (@group 0) (@binding 3) (light (texture_storage_2d rgba16float write)))

((var uniform) (@group 0) (@binding 4) (tracing Tracing))

(fn (@compute) (@workgroup_size 8 8) accumulate_main (((@builtin global_invocation_id) id vec3u))
    (let size (textureDimensions noisy))
    (if ((or (>= (get id x) (get size x)) (>= (get id y) (get size y))) (return)))
    (let pixel (vec2i (get id xy)))
    (let frames (f32 (get tracing frame z)))
    (let sample (textureLoad noisy pixel 0))
    (var average sample)
    (if ((> frames 0.0)
         (= average (/ (+ (* (textureLoad history pixel 0) frames) sample) (+ frames 1.0)))))
    (textureStore next pixel average)
    (textureStore light pixel average))
