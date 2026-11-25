;; First-hit direct lighting. In the temporal dispatch the input is
;; last frame's history and the output is scratch. In primary the input is
;; the completed scratch plane and the output is this frame's history.
((var storage read) (@group 0) (@binding 15) (reservoir_input (array SurfaceReservoir)))

((var storage read_write) (@group 0) (@binding 16) (reservoir_output (array SurfaceReservoir)))

(var (@group 0) (@binding 17) (motion (texture_2d f32)))

;; Fresh candidates for each pixel that actually traces a path.
(fn fresh_draws () (-> i32)
    (return (select 4 2 (!= (get tracing frame w) 0))))

(fn fresh_samples ((s Surface) (v vec3f) (seed (ptr function u32))) (-> Reservoir)
    (var (r Reservoir))
    (let fraction (mesh_fraction))
    (for ((var i 0) (< i (fresh_draws)) (+= i 1))
         (let draw (draw_proposal s v fraction seed))
         (let sample (LightSample (get draw direction) (dot (get draw value) env_luma)))
         (if ((reservoir_draw (address-of r) sample (get draw pdf) (random seed))
              (= (get r emitter) (get draw emitter))
              (= (get r coordinates) (get draw coordinates)))))
    (return r))

;; Clip z is affine in view-space depth for both camera projections.
;; Compare both surfaces in the donor's camera, before dividing by w.
(fn clip_depth ((camera_matrix mat4x4f) (position vec3f)) (-> f32)
    (return (get (* camera_matrix (vec4f position 1.0)) z)))

(fn compatible_reservoir ((p vec2i) (normal vec3f) (z f32) (triangle u32)) (-> Reservoir)
    (if ((or (any (< p (vec2i 0))) (any (>= p (vec2i (textureDimensions depth)))))
         (return (Reservoir))))
    (let site (at reservoir_input (pixel_index p)))
    (if ((or (and (!= triangle NONE) (!= triangle (u32 (get site triangle))))
             (< (dot (unfolded (get site normal)) normal) 0.9)
             (> (abs (- (get site clip_depth) z)) (* 0.02 (max (abs z) 0.001))))
         (return (Reservoir))))
    (return (get site reservoir)))

(fn reuse ((r (ptr function Reservoir)) (s Surface) (v vec3f) (donor Reservoir) (m i32) (u f32))
    (var target_value 0.0)
    (var candidate donor)
    (if ((> (get donor weight_sum) 0.0)
         (let draw (selected_proposal s v donor (mesh_fraction)))
         (= (get candidate selected direction) (get draw direction))
         (= target_value (dot (get draw value) env_luma))))
    (reservoir_merge r candidate target_value m u))

(fn temporal_reuse ((r (ptr function Reservoir)) (s Surface) (v vec3f) (p vec2i) (u f32))
    (let size (vec2f (textureDimensions depth)))
    (let q (- (+ (vec2f p) 0.5) (* (get (textureLoad motion p 0) xy) size)))
    (let z (get (textureLoad emission p 0) w))
    (let donor (compatible_reservoir (vec2i (floor q)) (get s normal) z
                                     (get (textureLoad triangles p 0) x)))
    ;; Fast screen motion leaves too little overlap for an old direction to
    ;; stand for twenty frames of proposals. Fresh samples take over quickly.
    (let travel (length (* (get (textureLoad motion p 0) xy) size)))
    (let cap (select
              (select 20 2 (== (get tracing frame z) 2))
              1
              (and (== (get tracing frame z) 2) (> travel 1.5))))
    (reuse r s v donor (min (get donor count) (* cap (fresh_draws))) u))

(fn column_parity ((y u32)) (-> u32)
    (return (bit-and (+ y (u32 (get tracing frame x))) 1u)))

;; In a checkerboard dispatch each lane covers one pixel of its row's parity.
(fn sample_pixel ((id vec2u)) (-> vec2u)
    (if ((== (get tracing frame w) 0) (return id)))
    (return (vec2u (+ (* 2u (get id x)) (column_parity (get id y))) (get id y))))

(fn (@compute)
    (@workgroup_size 8 8)
    temporal_reservoirs
    (((@builtin global_invocation_id) id vec3u))
    (let size (textureDimensions depth))
    (let p (vec2i (sample_pixel (get id xy))))
    (if ((any (>= (vec2u p) size)) (return)))
    (let i (pixel_index p))
    (let z (textureLoad depth p 0))
    (if ((or (>= z 1.0) (uncovered p))
         (= (at reservoir_output i) (SurfaceReservoir)) (return)))
    (let s (first_surface p z))
    (let v (normalize (- (get camera eye xyz) (get s position))))
    (var seed (seeded (+ i (u32 (get tracing frame y))) 2u))
    (var r (fresh_samples s v (address-of seed)))
    (if ((> (get tracing frame z) 0)
         (temporal_reuse (address-of r) s v p (random (address-of seed)))))
    (let depth_now (clip_depth (get camera view_projection) (get s position)))
    (= (at reservoir_output i)
       (SurfaceReservoir r
                         (get (textureLoad normals p 0) xy)
                         (i32 (get (textureLoad triangles p 0) x))
                         depth_now)))

;; The four axial neighbors for a full frame, the four diagonal neighbors
;; for a checkerboard. Every donor was written by this temporal dispatch,
;; including when the blended layer uses the same scratch plane.
(fn spatial_reservoir
    ((s Surface) (v vec3f) (p vec2i) (site SurfaceReservoir) (seed (ptr function u32)))
    (-> Reservoir)
    (var r (get site reservoir))
    (let offsets (array (vec2i -1 0) (vec2i 1 0) (vec2i 0 -1) (vec2i 0 1)
                        (vec2i -1 -1) (vec2i 1 1) (vec2i 1 -1) (vec2i -1 1)))
    (let start (* 4u (u32 (get tracing frame w))))
    (let q (+ p (at offsets (+ start (u32 (* 4.0 (random seed)))))))
    (let donor (compatible_reservoir q (get s normal) (get site clip_depth) NONE))
    (reuse (address-of r) s v donor (get donor count) (random seed))
    (return r))

(fn reservoir_shadow ((r Reservoir) (s Surface) (v vec3f) (air vec3f) (pixel u32) (seed u32))
    (var (draw Proposal))
    (if ((> (get r weight_sum) 0.0)
         (= draw (selected_proposal s v r (mesh_fraction)))
         (*= (get draw value) (reservoir_weight r))))
    (direct_shadow s v air draw pixel seed))
