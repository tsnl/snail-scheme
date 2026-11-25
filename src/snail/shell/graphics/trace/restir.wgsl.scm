;; First-hit direct lighting. In the temporal dispatch the input is
;; last frame's history and the output is scratch. In primary the input is
;; the completed scratch plane and the output is this frame's history.
((var storage read) (@group 0) (@binding 15) (reservoir_input (array SurfaceReservoir)))

((var storage read_write) (@group 0) (@binding 16) (reservoir_output (array SurfaceReservoir)))

(var (@group 0) (@binding 17) (motion (texture_2d f32)))

(const FRESH_DRAWS 4)

;; Both passes use the same independent exploration draw for this receiver.
;; An exploratory path scores unshadowed energy and still teaches history.
(fn sampling_history ((h VisibilityHistory) (pixel u32)) (-> VisibilityHistory)
    (let u (* (f32 (>> (seeded pixel 3u) 8u)) (/ 1.0 16777216.0)))
    (if ((< u (get wave guiding exploration)) (return (VisibilityHistory))))
    (return h))

(fn fresh_samples ((s Surface) (v vec3f) (h VisibilityHistory) (seed (ptr function u32)))
    (-> Reservoir)
    (var (r Reservoir))
    (let fraction (mesh_fraction))
    (for ((var i 0) (< i FRESH_DRAWS) (+= i 1))
         (let draw (draw_proposal s v fraction seed))
         (let sample (LightSample (get draw direction)
                                  (selection_energy h (get draw key) (get draw value))))
         (if ((reservoir_draw (address-of r) sample (get draw pdf) (random seed))
              (= (get r emitter) (max 0 (get draw key)))
              (= (get r coordinates) (get draw coordinates)))))
    (return r))

;; Clip z is affine in view-space depth for both camera projections.
;; Compare both surfaces in the donor's camera, before dividing by w.
(fn clip_depth ((camera_matrix mat4x4f) (position vec3f)) (-> f32)
    (return (get (* camera_matrix (vec4f position 1.0)) z)))

(fn compatible_site ((p vec2i) (normal vec3f) (z f32) (triangle u32)) (-> SurfaceReservoir)
    (if ((or (any (< p (vec2i 0))) (any (>= p (vec2i (textureDimensions depth)))))
         (return (SurfaceReservoir))))
    (let site (at reservoir_input (pixel_index p)))
    (if ((or (and (!= triangle NONE) (!= triangle (u32 (get site triangle))))
             (< (dot (unfolded (get site normal)) normal) 0.9)
             (> (abs (- (get site clip_depth) z)) (* 0.02 (max (abs z) 0.001))))
         (return (SurfaceReservoir))))
    (return site))

(fn reuse ((r (ptr function Reservoir)) (s Surface) (v vec3f) (h VisibilityHistory)
           (donor Reservoir) (m i32) (u f32))
    (var target_value 0.0)
    (var candidate donor)
    (if ((> (get donor weight_sum) 0.0)
         (let draw (selected_proposal s v donor (mesh_fraction)))
         (= (get candidate selected direction) (get draw direction))
         (= target_value (selection_energy h (get draw key) (get draw value)))))
    (reservoir_merge r candidate target_value m u))

(fn previous_site ((s Surface) (p vec2i) (travel vec2f)) (-> SurfaceReservoir)
    (if ((<= (get tracing reuse) 0) (return (SurfaceReservoir))))
    (let q (- (+ (vec2f p) 0.5) travel))
    (let z (get (textureLoad emission p 0) w))
    (return (compatible_site (vec2i (floor q)) (get s normal) z
                             (get (textureLoad triangles p 0) x))))

;; Fast motion leaves too little overlap for an old sample to stand for
;; twenty frames of proposals.
(fn temporal_count ((count i32) (travel vec2f)) (-> i32)
    (var cap (get wave guiding history_limit))
    (if ((== (get tracing reuse) 2)
         (= cap (min cap (select 2.0 1.0 (> (length travel) 1.5))))))
    (return (min count (i32 (* cap (f32 FRESH_DRAWS))))))

(fn (@compute)
    (@workgroup_size 8 8)
    temporal_reservoirs
    (((@builtin global_invocation_id) id vec3u))
    (let size (textureDimensions depth))
    (let p (vec2i (get id xy)))
    (if ((any (>= (vec2u p) size)) (return)))
    (let i (pixel_index p))
    (let z (textureLoad depth p 0))
    (if ((or (>= z 1.0) (uncovered p))
         (= (at reservoir_output i) (SurfaceReservoir)) (return)))
    (let s (first_surface p z))
    (let v (normalize (- (get camera eye xyz) (get s position))))
    (let index (+ i (u32 (get tracing layer_offset))))
    (let travel (* (get (textureLoad motion p 0) xy) (vec2f size)))
    (let previous (previous_site s p travel))
    (var visibility (get previous visibility))
    ;; Both paths shade the same rasterized point. The
    ;; second can already use the first shadow test at this exact pixel.
    (if ((> (get tracing sample_index) 0)
         (= visibility (get (at reservoir_input i) visibility))))
    (let h (sampling_history visibility index))
    (var seed (seeded index 2u))
    (var r (fresh_samples s v h (address-of seed)))
    (let donor (get previous reservoir))
    (if ((> (get donor count) 0)
         (reuse (address-of r) s v h donor (temporal_count (get donor count) travel)
                (random (address-of seed)))))
    (let depth_now (clip_depth (get camera view_projection) (get s position)))
    (= (at reservoir_output i)
       (SurfaceReservoir r
                         (get (textureLoad normals p 0) xy)
                         (i32 (get (textureLoad triangles p 0) x))
                         depth_now visibility)))

;; Each axial neighbor belongs to this temporal dispatch, including when
;; the blended layer uses the same scratch plane.
(fn spatial_reservoir
    ((s Surface) (v vec3f) (p vec2i) (site SurfaceReservoir) (h VisibilityHistory)
     (seed (ptr function u32)))
    (-> Reservoir)
    (var r (get site reservoir))
    (let offsets (array (vec2i -1 0) (vec2i 1 0) (vec2i 0 -1) (vec2i 0 1)))
    (let q (+ p (at offsets (u32 (* 4.0 (random seed))))))
    (let donor (get (compatible_site q (get s normal) (get site clip_depth) NONE) reservoir))
    (reuse (address-of r) s v h donor (get donor count) (random seed))
    (return r))

(fn reservoir_shadow ((r Reservoir) (s Surface) (v vec3f) (air vec3f) (h VisibilityHistory)
                      (pixel u32) (seed u32))
    (var (draw Proposal))
    (if ((> (get r weight_sum) 0.0)
         (= draw (selected_proposal s v r (mesh_fraction)))
         (*= (get draw value) (reservoir_weight r))))
    (direct_shadow s v air draw h pixel seed))
