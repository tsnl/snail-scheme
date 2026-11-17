;; Environments made on the device: decoded from a Radiance HDR file or
;; drawn from a sky, then given the tables that sample them by their
;; light (environment-light.wgsl.scm reads both).
;;
;;   unrle       one row of an HDR file's pixels a thread: each of the
;;               four channels' runs, a byte at a time, into a word of
;;               RGBE a pixel
;;   downsample  each texel of the environment, the average of the
;;               `factor` by `factor` decoded pixels it covers
;;   sky         each texel of a drawn sky: the sky's gradient, and the
;;               sun's disc by how much of the texel it covers, at the
;;               radiance that gives `sun_light` to a surface facing it
;;   weigh       one row of texels a thread: the cumulative distribution
;;               of its light, weighted by sin θ for the solid angle a
;;               texel spans, into the row of the table, and its sum
;;   marginal    one thread: the rows' cumulative distribution into the
;;               table's last column, and the total into its corner
;;
;; An environment is equirectangular: v from the zenith down, u around
;; from -z (environment-light.wgsl.scm). `EnvironmentShape` comes from
;; Pod: the file's size and the environment's, the factor, and the sky.
((var storage read) (@group 0) (@binding 0) (file (array u32)))

((var storage read) (@group 0) (@binding 1) (rows (array u32)))

((var storage read_write) (@group 0) (@binding 2) (rgbe (array u32)))

((var uniform) (@group 0) (@binding 3) (shape EnvironmentShape))

(var (@group 0) (@binding 4) (radiance (texture_storage_2d rgba32float write)))

(var (@group 0) (@binding 5) (light (texture_2d f32)))

((var storage read_write) (@group 0) (@binding 6) (sums (array f32)))

(var (@group 0) (@binding 7) (table (texture_storage_2d r32float write)))

(const PI 3.14159265358979)

;; ---- Decoding ----

(fn file_byte ((index u32)) (-> u32)
    (return (bit-and (>> (at file (>> index 2u)) (* (bit-and index 3u) 8u)) 255u)))

;; A row starts with 2, 2 and its width; then each channel in turn as
;; runs: a count over 128 repeats the next byte, a count up to 128 is
;; that many bytes as they are.
(fn (@compute) (@workgroup_size 64) unrle (((@builtin global_invocation_id) id vec3u))
    (let row (get id x))
    (let width (u32 (get shape size x)))
    (if ((>= row (u32 (get shape size y))) (return)))
    (var at_byte (+ (at rows row) 4u))
    (for ((var channel 0u) (< channel 4u) (+= channel 1u))
      (var x 0u)
      (while (< x width)
        (var count (file_byte at_byte))
        (+= at_byte 1u)
        (let repeated (> count 128u))
        (if (repeated (-= count 128u)))
        (let value (file_byte at_byte))
        (for ((var k 0u) (and (< k count) (< x width)) (+= k 1u))
          (let byte (select (file_byte (+ at_byte k)) value repeated))
          (let pixel (+ (* row width) x))
          (let shift (* channel 8u))
          (if ((== channel 0u) (= (at rgbe pixel) byte))
              (else (= (at rgbe pixel) (bit-or (at rgbe pixel) (<< byte shift)))))
          (+= x 1u))
        (+= at_byte (select count 1u repeated)))))

(fn decoded ((word u32)) (-> vec3f)
    (let e (>> word 24u))
    (if ((== e 0u) (return (vec3f 0.0))))
    (let scale (ldexp 1.0 (- (i32 e) 136)))
    (return (* (vec3f (f32 (bit-and word 255u)) (f32 (bit-and (>> word 8u) 255u)) (f32 (bit-and (>> word 16u) 255u))) scale)))

(fn (@compute) (@workgroup_size 8 8) downsample (((@builtin global_invocation_id) id vec3u))
    (if ((or (>= (i32 (get id x)) (get shape size z)) (>= (i32 (get id y)) (get shape size w))) (return)))
    (let f (u32 (get shape factor x)))
    (var sum (vec3f 0.0))
    (for ((var dy 0u) (< dy f) (+= dy 1u))
      (for ((var dx 0u) (< dx f) (+= dx 1u))
        (let x (+ (* (get id x) f) dx))
        (let y (+ (* (get id y) f) dy))
        (+= sum (decoded (at rgbe (+ (* y (u32 (get shape size x))) x))))))
    (textureStore radiance (vec2i (get id xy)) (vec4f (/ sum (f32 (* f f))) 1.0)))

;; ---- Drawing a sky ----

(fn direction_at ((uv vec2f)) (-> vec3f)
    (let phi (* (- (get uv x) 0.5) 2.0 PI))
    (let theta (* (get uv y) PI))
    (return (vec3f (* (sin theta) (sin phi)) (cos theta) (* (- (sin theta)) (cos phi)))))

(fn gradient ((d vec3f)) (-> vec3f)
    (let up (get d y))
    (if ((< up 0.0) (return (* (get shape ground xyz) (get shape ground w)))))
    (return (* (mix (get shape horizon xyz) (get shape zenith xyz) (pow up 0.5)) (get shape zenith w))))

;; The sun's disc covers a few texels, so each is sampled at 4 by 4
;; points and lit by the share inside it.
(fn (@compute) (@workgroup_size 8 8) sky (((@builtin global_invocation_id) id vec3u))
    (let size (vec2f (f32 (get shape size z)) (f32 (get shape size w))))
    (if ((or (>= (f32 (get id x)) (get size x)) (>= (f32 (get id y)) (get size y))) (return)))
    (var inside 0.0)
    (for ((var k 0) (< k 16) (+= k 1))
      (let offset (/ (+ (vec2f (f32 (bit-and k 3)) (f32 (>> k 2))) 0.5) 4.0))
      (if ((>= (dot (direction_at (/ (+ (vec2f (get id xy)) offset) size)) (get shape sun xyz)) (get shape sun w))
           (+= inside 1.0))))
    (let solid (* 2.0 PI (- 1.0 (get shape sun w))))
    (let sun (* (get shape sun_light xyz) (/ (/ inside 16.0) solid)))
    (let d (direction_at (/ (+ (vec2f (get id xy)) 0.5) size)))
    (textureStore radiance (vec2i (get id xy)) (vec4f (+ (gradient d) sun) 1.0)))

;; ---- Tables ----

(fn weight_of ((c vec3f) (row u32) (height u32)) (-> f32)
    (return (* (dot c (vec3f 0.2126 0.7152 0.0722)) (sin (* PI (/ (+ (f32 row) 0.5) (f32 height)))))))

(fn (@compute) (@workgroup_size 64) weigh (((@builtin global_invocation_id) id vec3u))
    (let size (textureDimensions light))
    (let row (get id x))
    (if ((>= row (get size y)) (return)))
    (var sum 0.0)
    (for ((var x 0u) (< x (get size x)) (+= x 1u))
      (+= sum (weight_of (get (textureLoad light (vec2u x row) 0) xyz) row (get size y))))
    (var running 0.0)
    (for ((var x 0u) (< x (get size x)) (+= x 1u))
      (+= running (weight_of (get (textureLoad light (vec2u x row) 0) xyz) row (get size y)))
      (textureStore table (vec2u x row) (vec4f (select (/ (f32 (+ x 1u)) (f32 (get size x))) (/ running sum) (> sum 0.0)))))
    (= (at sums row) sum))

(fn (@compute) (@workgroup_size 1) marginal ()
    (let size (textureDimensions light))
    (var total 0.0)
    (for ((var y 0u) (< y (get size y)) (+= y 1u)) (+= total (at sums y)))
    (var running 0.0)
    (for ((var y 0u) (< y (get size y)) (+= y 1u))
      (+= running (at sums y))
      (textureStore table (vec2u (get size x) y) (vec4f (/ running (max total 1e-30)))))
    (textureStore table (get size xy) (vec4f total)))
