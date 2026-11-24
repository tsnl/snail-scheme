;; A path from every pixel, traced as a wavefront: each step is one
;; kernel over a queue of rays, so a step's invocations do the same work
;; and a bounce runs only as many invocations as paths remain. The first
;; hits come from the G-buffer (surface.wgsl.scm), later ones from the ray
;; queries of (snail shell graphics bvh). The renderer is enlighten's
;; (tsnl/enlighten, archive/main-v1): metallic-roughness shading, Lambert
;; diffuse and GGX reflection sampled by visible normals, mixed with one
;; probability at every vertex; light from the environment
;; (environment-light.wgsl.scm), resampled at first hits by biased ReSTIR
;; (restir.wgsl.scm), sampled at later hits with a shadow ray, and seen
;; by rays that leave the scene, the two direct-light strategies
;; weighted by multiple importance sampling (the power heuristic);
;; emission wherever a path hits it; Russian roulette after the third
;; bounce; textures at the level of the ray cone's footprint.
;;
;;   primary    from each pixel's first hit: its emission, or the
;;              environment behind it, into `radiance`; a shadow ray
;;              toward the environment into `shadows`; and the scattered
;;              ray into `outgoing`
;;   connect    the environment's light, where a shadow ray met nothing,
;;              into `radiance` (after the queries' `occlude`)
;;   shade      at each ray's hit (after `intersect`): the environment
;;              if it met nothing, else the surface's emission, then, but
;;              on the last bounce, a shadow ray and the next ray, as
;;              `primary`
;;   gather     `radiance` into the `noisy` plane
;;
;; The blended surfaces' layer (surface.wgsl.scm) is traced the same way
;; after the first hits, from its own G-buffer into its own noisy plane,
;; its radiance a pixel count past theirs.
;;
;; A frame runs temporal_reservoirs and primary, then for each bounce
;; occlude, connect, intersect and shade, then gather. A pixel has at most
;; one ray in a queue, so adding to its radiance needs no atomics. Rays are
;; appended with an atomic count each: bounce b's rays and shadow rays count at `slots.y`
;; and `slots.z` of `wave`, the rays a shade reads at `slots.x`. A step
;; over a queue is dispatched over its capacity, a ray a pixel, and
;; invocations past the count return (bvh.sld says why not indirectly).
;;
;; A ray's `payload` is the path's weight and its pixel's index, `more`
;; the cone's width at the ray's origin, its spread, and the density it
;; was scattered with; a shadow ray's `payload` the light it brings and
;; its pixel. `Camera3D`, `Tracing`, `Wave` and `SurfaceMaterial` come
;; from Pod; the scene is group 1 (scene.wgsl.scm), the environment
;; group 2.
(struct RayHit
        (t f32)
        (triangle u32)
        (barycentric vec2f))

(struct Ray
        (origin vec4f)
        (direction vec4f)
        (hit RayHit)
        (payload vec4f)
        (more vec4f))

(const NONE 4294967295u)

(const PI 3.14159265358979)

((var uniform) (@group 0) (@binding 0) (camera Camera3D))

((var uniform) (@group 0) (@binding 1) (tracing Tracing))

((var uniform) (@group 0) (@binding 2) (wave Wave))

((var storage read) (@group 0) (@binding 3) (incoming (array Ray)))

((var storage read_write) (@group 0) (@binding 4) (outgoing (array Ray)))

((var storage read_write) (@group 0) (@binding 5) (shadows (array Ray)))

((var storage read_write) (@group 0) (@binding 6) (counts (array (atomic u32))))

((var storage read_write) (@group 0) (@binding 7) (radiance (array vec4f)))

(var (@group 0) (@binding 8) (triangles (texture_2d u32)))

(var (@group 0) (@binding 9) (normals (texture_2d f32)))

(var (@group 0) (@binding 10) (emission (texture_2d f32)))

(var (@group 0) (@binding 11) (albedo (texture_2d f32)))

(var (@group 0) (@binding 12) (roughness (texture_2d f32)))

(var (@group 0) (@binding 13) (depth texture_depth_2d))

(var (@group 0) (@binding 14) (noisy (texture_storage_2d rgba16float write)))

;; ---- Surfaces ----

;; What shading needs at a hit: where, its normals, the material's
;; colors and factors, and whether it emits.
(struct Surface
        (position vec3f)
        (normal vec3f)
        (geometric vec3f)
        (albedo vec3f)
        (emission vec3f)
        (metallic f32)
        (roughness f32))

(fn unfolded ((e vec2f)) (-> vec3f)
    (var n (vec3f (get e x) (get e y) (- 1.0 (abs (get e x)) (abs (get e y)))))
    (let t (max (- (get n z)) 0.0))
    (+= (get n x) (select t (- t) (>= (get n x) 0.0)))
    (+= (get n y) (select t (- t) (>= (get n y) 0.0)))
    (return (normalize n)))

;; Where depth `z` at `pixel` puts its first hit. Depth is finest near the
;; eye: tens of units away it misses the surface by more than `leaving`
;; lifts a ray off it, and the ray would meet the surface it leaves.
(fn depth_point ((pixel vec2i) (z f32)) (-> vec3f)
    (let size (vec2f (textureDimensions depth)))
    (let ndc (vec2f (- (* (/ (+ (vec2f pixel) 0.5) size) 2.0) 1.0)))
    (let clip (* (get camera inverse) (vec4f (get ndc x) (- (get ndc y)) z 1.0)))
    (return (/ (get clip xyz) (get clip w))))

;; The first hit at `pixel`: the depth's point moved onto the plane of the
;; triangle drawn there, whose normal, facing the eye, is the geometric
;; one; its shading and material from the G-buffer.
(fn first_surface ((pixel vec2i) (z f32)) (-> Surface)
    (let p (depth_point pixel z))
    (let triangle (get (textureLoad triangles pixel 0) x))
    (let a (get (corner triangle 0u) position))
    (var geometric (normalize (cross (- (get (corner triangle 1u) position) a)
                                     (- (get (corner triangle 2u) position) a))))
    (if ((< (dot geometric (- (get camera eye xyz) p)) 0.0) (= geometric (- geometric))))
    (let m (textureLoad roughness pixel 0))
    (var (s Surface))
    (= (get s position) (- p (* geometric (dot (- p a) geometric))))
    (= (get s normal) (unfolded (get (textureLoad normals pixel 0) xy)))
    (= (get s geometric) geometric)
    (= (get s albedo) (get (textureLoad albedo pixel 0) xyz))
    (= (get s metallic) (get m x))
    (= (get s roughness) (get m y))
    (return s))

;; The texture level a ray cone of width `width` at a hit covers: the
;; triangle's texels per unit of world area, scaled by how obliquely the
;; cone meets it.
(fn level_at ((a Vertex) (b Vertex) (c Vertex) (width f32) (facing f32)) (-> f32)
    (let world (length
                (cross (- (get b position) (get a position))
                       (- (get c position) (get a position)))))
    (let du (- (uv_of b) (uv_of a)))
    (let dv (- (uv_of c) (uv_of a)))
    (let texels (* (abs (- (* (get du x) (get dv y)) (* (get du y) (get dv x))))
                   (* (get tracing view y) (get tracing view y))))
    (let ratio (/ texels (max world 1e-20)))
    (return
     (max 0.0 (+ (* 0.5 (log2 (max ratio 1e-20))) (log2 (/ (max width 1e-8) (max facing 0.05)))))))

;; A later hit, from the triangle and its barycentrics, facing `toward`.
(fn hit_surface ((triangle u32) (b vec2f) (toward vec3f) (width f32)) (-> Surface)
    (let a (corner triangle 0u))
    (let bb (corner triangle 1u))
    (let c (corner triangle 2u))
    (let w (- 1.0 (get b x) (get b y)))
    (let m (at materials (get a material)))
    (var geometric
         (normalize
          (cross (- (get bb position) (get a position)) (- (get c position) (get a position)))))
    (if ((< (dot geometric toward) 0.0) (= geometric (- geometric))))
    (var normal (+ (* (get a normal) w) (* (get bb normal) (get b x)) (* (get c normal) (get b y))))
    (if ((< (dot normal normal) 1e-12) (= normal geometric)))
    (= normal (normalize normal))
    (if ((< (dot normal geometric) 0.0) (= normal (- normal))))
    (if ((!= (get m flags y) 0)
         (let position (+
                        (+ (* (get a position) w) (* (get bb position) (get b x)))
                        (* (get c position) (get b y))))
         (= normal (water_normal position geometric (get camera scene_time)
                                 (/ width (max 0.05 (abs (dot geometric toward))))))))
    (let uv (+ (* (uv_of a) w) (* (uv_of bb) (get b x)) (* (uv_of c) (get b y))))
    (let level (level_at a bb c width (abs (dot geometric toward))))
    (let base (texel (get m textures x) uv level))
    (let metal_rough (texel (get m textures y) uv level))
    (var (s Surface))
    (= (get s normal) normal)
    (= (get s geometric) geometric)
    (= (get s albedo) (* (get m base_color xyz) (decoded (get base xyz))))
    (= (get s emission)
       (* (get m emissive xyz) (decoded (get (texel (get m textures w) uv level) xyz))))
    (= (get s metallic) (* (get m factors x) (get metal_rough z)))
    (= (get s roughness) (* (get m factors y) (get metal_rough y)))
    (return s))

;; The ray leaves `s` from just above its surface, on the side it goes.
(fn leaving ((s Surface) (direction vec3f)) (-> vec3f)
    (let lift (*
               1e-4
               (max 1.0
                    (max (abs (get s position x))
                         (max (abs (get s position y)) (abs (get s position z)))))))
    (return (+ (get s position)
               (* (get s geometric)
                  (select (- lift) lift (>= (dot direction (get s geometric)) 0.0))))))

;; ---- Light ----

;; The power heuristic's weight for a sample of density `chosen` that
;; the other strategy would take with density `other`.
(fn balanced ((chosen f32) (other f32)) (-> f32)
    (let c2 (* chosen chosen))
    (return (/ c2 (max (+ c2 (* other other)) 1e-30))))

;; ---- Scattering ----

;; An orthonormal frame around n (Duff et al. 2017).
(fn frame_of ((n vec3f)) (-> mat3x3f)
    (let sign (select -1.0 1.0 (>= (get n z) 0.0)))
    (let a (/ -1.0 (+ sign (get n z))))
    (let b (* (get n x) (get n y) a))
    (return
     (mat3x3f (vec3f (+ 1.0 (* sign (get n x) (get n x) a)) (* sign b) (* (- sign) (get n x)))
              (vec3f b (+ sign (* (get n y) (get n y) a)) (- (get n y)))
              n)))

(fn alpha_of ((s Surface)) (-> f32)
    (return (max (* (get s roughness) (get s roughness)) 0.002)))

(fn reflectance ((s Surface)) (-> vec3f)
    (return (mix (vec3f 0.04) (get s albedo) (get s metallic))))

(fn ggx ((alpha f32) (nh f32)) (-> f32)
    (let a2 (* alpha alpha))
    (let d (+ (* nh nh (- a2 1.0)) 1.0))
    (return (/ a2 (* PI d d))))

(fn masking ((alpha f32) (nv f32)) (-> f32)
    (let a2 (* alpha alpha))
    (return (/ (* 2.0 nv) (+ nv (sqrt (+ a2 (* (- 1.0 a2) nv nv)))))))

;; The BSDF times the cosine toward `l`.
(fn evaluated ((s Surface) (v vec3f) (l vec3f)) (-> vec3f)
    (let nl (dot (get s normal) l))
    (let nv (dot (get s normal) v))
    (if ((or (<= nl 0.0) (<= nv 0.0)) (return (vec3f 0.0))))
    (let h (normalize (+ v l)))
    (let alpha (alpha_of s))
    (let fresnel (+
                  (reflectance s)
                  (* (- (vec3f 1.0) (reflectance s)) (pow (- 1.0 (max (dot v h) 0.0)) 5.0))))
    (let specular (/
                   (* fresnel
                      (ggx alpha (max (dot (get s normal) h) 0.0))
                      (masking alpha nv)
                      (masking alpha nl))
                   (* 4.0 nv nl)))
    (let diffuse (* (- (vec3f 1.0) fresnel) (- 1.0 (get s metallic)) (/ (get s albedo) PI)))
    (return (* (+ diffuse specular) nl)))

;; How often reflection is sampled rather than diffusion.
(fn specular_odds ((s Surface)) (-> f32)
    (let f (dot (reflectance s) (vec3f 0.3333)))
    (let d (* (dot (get s albedo) (vec3f 0.3333)) (- 1.0 (get s metallic))))
    (return (clamp (/ f (+ f d 1e-4)) 0.1 0.9)))

(fn density ((s Surface) (v vec3f) (l vec3f)) (-> f32)
    (let nl (dot (get s normal) l))
    (let nv (dot (get s normal) v))
    (if ((or (<= nl 0.0) (<= nv 0.0)) (return 0.0)))
    (let h (normalize (+ v l)))
    (let alpha (alpha_of s))
    (let reflect (/ (* (ggx alpha (max (dot (get s normal) h) 0.0)) (masking alpha nv)) (* 4.0 nv)))
    (let odds (specular_odds s))
    (return (+ (* odds reflect) (* (- 1.0 odds) (/ nl PI)))))

;; A visible normal of GGX (Heitz 2018), in the frame where z is n.
(fn visible_normal ((v vec3f) (alpha f32) (r vec2f)) (-> vec3f)
    (let vh (normalize (vec3f (* alpha (get v x)) (* alpha (get v y)) (get v z))))
    (let lensq (+ (* (get vh x) (get vh x)) (* (get vh y) (get vh y))))
    (let t1 (select
             (vec3f 1.0 0.0 0.0)
             (/ (vec3f (- (get vh y)) (get vh x) 0.0) (sqrt lensq))
             (> lensq 0.0)))
    (let t2 (cross vh t1))
    (let radius (sqrt (get r x)))
    (let phi (* 2.0 PI (get r y)))
    (let p1 (* radius (cos phi)))
    (let s (* 0.5 (+ 1.0 (get vh z))))
    (let p2 (+ (* (- 1.0 s) (sqrt (- 1.0 (* p1 p1)))) (* s radius (sin phi))))
    (let nh (+ (* t1 p1) (* t2 p2) (* vh (sqrt (max 0.0 (- 1.0 (* p1 p1) (* p2 p2)))))))
    (return (normalize (vec3f (* alpha (get nh x)) (* alpha (get nh y)) (max 0.0 (get nh z))))))

(fn scattered ((s Surface) (v vec3f) (seed (ptr function u32))) (-> vec3f)
    (let frame (frame_of (get s normal)))
    (let r (vec2f (random seed) (random seed)))
    (if ((< (random seed) (specular_odds s))
         (let local_v (* (transpose frame) v))
         (let m (visible_normal local_v (alpha_of s) r))
         (return (reflect (- v) (* frame m)))))
    (let radius (sqrt (get r x)))
    (let phi (* 2.0 PI (get r y)))
    (return (* frame
               (vec3f (* radius (cos phi))
                      (* radius (sin phi))
                      (sqrt (max 0.0 (- 1.0 (get r x))))))))

;; Whether every component is a number and not infinite: a NaN fails both
;; comparisons.
(fn finite3 ((v vec3f)) (-> bool)
    (return (and (all (< (abs v) (vec3f 1e30))) (all (>= (abs v) (vec3f 0.0))))))

;; ---- Queues ----

;; Rows hold 65535 workgroups of 64, every row but the last full.
(fn queue_item ((id vec3u)) (-> u32)
    (return (+ (get id x) (* (get id y) 4194240u))))

(fn seeded ((pixel u32) (salt u32)) (-> u32)
    (return (pcg (bit-xor pixel
                          (pcg (+ (* (u32 (get tracing frame x)) 64u)
                                  (* (u32 (get wave step x)) 4u)
                                  salt))))))

(fn ray_from ((s Surface) (direction vec3f) (seed u32) (payload vec4f) (more vec4f)) (-> Ray)
    (return (Ray (vec4f (leaving s direction) 1e30)
                 (vec4f direction ((bitcast f32) seed))
                 (RayHit 0.0 0u (vec2f 0.0))
                 payload
                 more)))

(fn shadow_ray ((s Surface) (d vec3f) (light vec3f) (pixel u32) (seed u32))
    (let slot (atomicAdd (address-of (at counts (u32 (get wave slots z)))) 1u))
    (= (at shadows slot) (ray_from s d seed (vec4f light ((bitcast f32) pixel)) (vec4f 0.0))))

;; The environment proposal at later bounces.
(fn sample_environment
    ((s Surface) (v vec3f) (path_weight vec3f) (pixel u32) (seed (ptr function u32)))
    (let chosen (environment_sample
                 (vec4f (random seed) (random seed) (random seed) (random seed))))
    (let toward (get chosen xyz))
    (let f (evaluated s v toward))
    (if ((and (> (get chosen w) 0.0) (> (dot f f) 0.0))
         (let light (*
                     (environment_light toward)
                     (/ (balanced (get chosen w) (density s v toward)) (get chosen w))))
         (shadow_ray s toward (* path_weight f light) pixel (pcg (deref seed))))))

(fn scatter_ray
    ((s Surface)
     (v vec3f)
     (path_weight vec3f)
     (pixel u32)
     (width f32)
     (spread f32)
     (seed (ptr function u32)))
    (let l (scattered s v seed))
    (let p (density s v l))
    (if ((not (and (> p 1e-6) (finite3 l) (> (dot l (get s geometric)) 0.0))) (return)))
    (var weight (/ (* path_weight (evaluated s v l)) p))
    (if ((not (finite3 weight)) (return)))
    (if ((> (get wave step x) 2)
         (let survive (clamp (max (get weight x) (max (get weight y) (get weight z))) 0.05 0.95))
         (if ((> (random seed) survive) (return)))
         (/= weight survive)))
    (let slot (atomicAdd (address-of (at counts (u32 (get wave slots y)))) 1u))
    (= (at outgoing slot)
       (ray_from s
                 l
                 (pcg (deref seed))
                 (vec4f weight ((bitcast f32) pixel))
                 (vec4f width (+ spread (* 0.25 (get s roughness))) p 0.0))))

;; ---- Steps ----

(fn pixel_index ((pixel vec2i)) (-> u32)
    (return (+ (u32 (get pixel x)) (* (u32 (get pixel y)) (get (textureDimensions depth) x)))))

(fn uncovered ((pixel vec2i)) (-> bool)
    (return (and (> (get tracing frame y) 0) (== (get (textureLoad albedo pixel 0) w) 0.0))))

;; The first hits' paths, or the layer's: `tracing.frame.y` is where the
;; wave's radiance starts, 0 for the first hits and a pixel count past
;; them for the layer's, whose pixels with no blended surface, their
;; alpha 0, make no path.
(fn (@compute) (@workgroup_size 8 8) primary (((@builtin global_invocation_id) id vec3u))
    (let size (textureDimensions depth))
    (let pixel (vec2i (sample_pixel (get id xy))))
    (if ((any (>= (vec2u pixel) size)) (return)))
    (let i (pixel_index pixel))
    (let index (+ i (u32 (get tracing frame y))))
    (var site (at reservoir_input i))
    (if ((== (get site reservoir count) 0)
         (= (at reservoir_output i) site)
         (if ((uncovered pixel) (= (at radiance index) (vec4f 0.0)) (return)))
         (let ndc (- (* (/ (+ (vec2f pixel) 0.5) (vec2f size)) 2.0) 1.0))
         (let far (* (get camera inverse) (vec4f (get ndc x) (- (get ndc y)) 1.0 1.0)))
         (= (at radiance index)
            (vec4f
             (environment_light (normalize (- (/ (get far xyz) (get far w)) (get camera eye xyz))))
             1.0))
         (return)))
    (let s (first_surface pixel (textureLoad depth pixel 0)))
    (= (at radiance index) (textureLoad emission pixel 0))
    (var seed (seeded index 0u))
    (let v (normalize (- (get camera eye xyz) (get s position))))
    (= (get site reservoir) (spatial_reservoir s v pixel site (address-of seed)))
    (= (at reservoir_output i) site)
    (reservoir_shadow (get site reservoir) s v index (pcg seed))
    (let spread (get tracing view x))
    (scatter_ray s
                 v
                 (vec3f 1.0)
                 index
                 (* spread (distance (get camera eye xyz) (get s position)))
                 spread
                 (address-of seed)))

(fn (@compute) (@workgroup_size 64) connect (((@builtin global_invocation_id) id vec3u))
    (let i (queue_item id))
    (if ((>= i (atomicLoad (address-of (at counts (u32 (get wave slots z)))))) (return)))
    (let ray (at shadows i))
    (if ((== (get ray hit triangle) NONE)
         (let pixel ((bitcast u32) (get ray payload w)))
         (+= (at radiance pixel) (vec4f (get ray payload xyz) 0.0)))))

(fn (@compute) (@workgroup_size 64) shade (((@builtin global_invocation_id) id vec3u))
    (let i (queue_item id))
    (if ((>= i (atomicLoad (address-of (at counts (u32 (get wave slots x)))))) (return)))
    (let ray (at incoming i))
    (let pixel ((bitcast u32) (get ray payload w)))
    (let weight (get ray payload xyz))
    (let l (get ray direction xyz))
    (let triangle (get ray hit triangle))
    (if ((== triangle NONE)
         (let seen (balanced (get ray more z) (environment_pdf l)))
         (+= (at radiance pixel) (vec4f (* weight (environment_light l) seen) 0.0))
         (return)))
    (let width (+ (get ray more x) (* (get ray more y) (get ray hit t))))
    (var s (hit_surface triangle (get ray hit barycentric) (- l) width))
    (= (get s position) (+ (get ray origin xyz) (* l (get ray hit t))))
    (+= (at radiance pixel) (vec4f (* weight (get s emission)) 0.0))
    (if ((!= (get wave step y) 0) (return)))
    (var seed (seeded pixel 1u))
    (sample_environment s (- l) weight pixel (address-of seed))
    (scatter_ray s (- l) weight pixel width (get ray more y) (address-of seed)))

(fn (@compute) (@workgroup_size 8 8) gather (((@builtin global_invocation_id) id vec3u))
    (let size (textureDimensions depth))
    (if ((or (>= (get id x) (get size x)) (>= (get id y) (get size y))) (return)))
    (let pixel (vec2i (get id xy)))
    (let index (+ (pixel_index pixel) (u32 (get tracing frame y))))
    ;; A held pixel still has its last radiance in this layer's slot.
    ;; Mark it so SVGF keeps the sample count that produced its history.
    (let held (and (!= (get tracing frame w) 0)
                   (!= (bit-and (get id x) 1u) (column_parity (get id y)))))
    (textureStore noisy pixel (vec4f (get (at radiance index) xyz) (select 1.0 -1.0 held))))
