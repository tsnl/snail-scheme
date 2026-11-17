;; One path per pixel through a scene, from the first hit the G-buffer
;; holds (surface.wgsl.scm), each later hit found by walking the BVH
;; (bvh.wgsl.scm) in this shader, since WebGPU has no ray queries. The
;; renderer is enlighten's (tsnl/enlighten, archive/main-v1): rasterized
;; first hits, then a Monte Carlo path with metallic-roughness shading,
;; Lambert diffuse and GGX reflection sampled by visible normals, mixed
;; with one probability at every vertex.
;;
;; Light: the sun, a small disc sampled at every vertex with a shadow
;; ray; the sky, a gradient a scattered ray sees when it leaves the
;; scene; and emissive surfaces, wherever a path hits them. Russian
;; roulette ends paths after the third bounce. A masked or blended
;; material's cutout is tested as rays cross it, so leaves cast the
;; shadows of their texture. Textures are sampled at the level of the ray
;; cone's footprint.
;;
;; `Camera3D`, `Tracing` and `SurfaceMaterial` come from Pod. The noisy
;; radiance goes to `noisy` for the filters to clean.
(struct Vertex
        (position vec3f)
        (u f32)
        (normal vec3f)
        (v f32)
        (tangent vec4f)
        (material u32)
        (pad0 u32)
        (pad1 u32)
        (pad2 u32))

(struct Node
        (left_low vec3f)
        (left u32)
        (left_high vec3f)
        (right u32)
        (right_low vec3f)
        (pad0 u32)
        (right_high vec3f)
        (pad1 u32))

(const TRIANGLE 2147483648u)

(const NONE 4294967295u)

(const PI 3.14159265358979)

((var uniform) (@group 0) (@binding 0) (camera Camera3D))

((var uniform) (@group 0) (@binding 1) (tracing Tracing))

((var storage read) (@group 0) (@binding 2) (vertices (array Vertex)))

((var storage read) (@group 0) (@binding 3) (indices (array u32)))

((var storage read) (@group 0) (@binding 4) (nodes (array Node)))

((var storage read) (@group 0) (@binding 5) (materials (array SurfaceMaterial)))

(var (@group 0) (@binding 6) (layers (texture_2d_array f32)))

(var (@group 0) (@binding 7) (repeat sampler))

(var (@group 0) (@binding 8) (normals (texture_2d f32)))

(var (@group 0) (@binding 9) (emission (texture_2d f32)))

(var (@group 0) (@binding 10) (albedo (texture_2d f32)))

(var (@group 0) (@binding 11) (roughness (texture_2d f32)))

(var (@group 0) (@binding 12) (depth texture_depth_2d))

(var (@group 0) (@binding 13) (noisy (texture_storage_2d rgba16float write)))

;; ---- Random numbers ----

(fn pcg ((value u32)) (-> u32)
    (let state (+ (* value 747796405u) 2891336453u))
    (let word (* (bit-xor (>> state (+ (>> state 28u) 4u)) state) 277803737u))
    (return (bit-xor (>> word 22u) word)))

(fn random ((seed (ptr function u32))) (-> f32)
    (= (deref seed) (pcg (deref seed)))
    (return (* (f32 (>> (deref seed) 8u)) (/ 1.0 16777216.0))))

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

(fn decoded ((c vec3f)) (-> vec3f)
    (return (select (pow (/ (+ c 0.055) 1.055) (vec3f 2.4)) (/ c 12.92) (<= c (vec3f 0.04045)))))

(fn texel ((layer i32) (uv vec2f) (level f32)) (-> vec4f)
    (if ((< layer 0) (return (vec4f 1.0))))
    (return (textureSampleLevel layers repeat uv layer level)))

;; The first hit, from the G-buffer and depth at `pixel`.
(fn first_surface ((pixel vec2i) (z f32)) (-> Surface)
    (let size (vec2f (textureDimensions depth)))
    (let ndc (vec2f (- (* (/ (+ (vec2f pixel) 0.5) size) 2.0) 1.0)))
    (let clip (* (get camera inverse) (vec4f (get ndc x) (- (get ndc y)) z 1.0)))
    (let packed (textureLoad normals pixel 0))
    (let m (textureLoad roughness pixel 0))
    (var (s Surface))
    (= (get s position) (/ (get clip xyz) (get clip w)))
    (= (get s normal) (unfolded (get packed xy)))
    (= (get s geometric) (unfolded (get packed zw)))
    (= (get s albedo) (get (textureLoad albedo pixel 0) xyz))
    (= (get s emission) (get (textureLoad emission pixel 0) xyz))
    (= (get s metallic) (get m x))
    (= (get s roughness) (get m y))
    (return s))

;; A triangle's corner.
(fn corner ((triangle u32) (k u32)) (-> Vertex)
    (return (at vertices (at indices (+ (* triangle 3u) k)))))

(fn uv_of ((v Vertex)) (-> vec2f)
    (return (vec2f (get v u) (get v v))))

;; The texture level a ray cone of width `width` at a hit covers: the
;; triangle's texels per unit of world area, scaled by how obliquely the
;; cone meets it.
(fn level_at ((a Vertex) (b Vertex) (c Vertex) (width f32) (facing f32)) (-> f32)
    (let world (length (cross (- (get b position) (get a position)) (- (get c position) (get a position)))))
    (let du (- (uv_of b) (uv_of a)))
    (let dv (- (uv_of c) (uv_of a)))
    (let texels (* (abs (- (* (get du x) (get dv y)) (* (get du y) (get dv x))))
                   (* (get tracing view y) (get tracing view y))))
    (let ratio (/ texels (max world 1e-20)))
    (return (max 0.0 (+ (* 0.5 (log2 (max ratio 1e-20))) (log2 (/ (max width 1e-8) (max facing 0.05)))))))

;; A later hit, from the triangle and its barycentrics, facing `toward`.
(fn hit_surface ((triangle u32) (b vec2f) (toward vec3f) (width f32)) (-> Surface)
    (let a (corner triangle 0u))
    (let bb (corner triangle 1u))
    (let c (corner triangle 2u))
    (let w (- 1.0 (get b x) (get b y)))
    (let m (at materials (get a material)))
    (var geometric (normalize (cross (- (get bb position) (get a position)) (- (get c position) (get a position)))))
    (if ((< (dot geometric toward) 0.0) (= geometric (- geometric))))
    (var normal (+ (* (get a normal) w) (* (get bb normal) (get b x)) (* (get c normal) (get b y))))
    (if ((< (dot normal normal) 1e-12) (= normal geometric)))
    (= normal (normalize normal))
    (if ((< (dot normal geometric) 0.0) (= normal (- normal))))
    (let uv (+ (* (uv_of a) w) (* (uv_of bb) (get b x)) (* (uv_of c) (get b y))))
    (let level (level_at a bb c width (abs (dot geometric toward))))
    (let base (texel (get m textures x) uv level))
    (let metal_rough (texel (get m textures y) uv level))
    (var (s Surface))
    (= (get s normal) normal)
    (= (get s geometric) geometric)
    (= (get s albedo) (* (get m base_color xyz) (decoded (get base xyz))))
    (= (get s emission) (* (get m emissive xyz) (decoded (get (texel (get m textures w) uv level) xyz))))
    (= (get s metallic) (* (get m factors x) (get metal_rough z)))
    (= (get s roughness) (* (get m factors y) (get metal_rough y)))
    (return s))

;; ---- Rays ----

(struct Hit
        (t f32)
        (triangle u32)
        (barycentric vec2f))

;; Whether a cutout lets the ray through where it crosses `triangle`.
(fn passes ((triangle u32) (b vec2f) (seed (ptr function u32))) (-> bool)
    (let a (corner triangle 0u))
    (let m (at materials (get a material)))
    (let mode (get m factors w))
    (if ((== mode 0.0) (return false)))
    (let bb (corner triangle 1u))
    (let c (corner triangle 2u))
    (let uv (+ (* (uv_of a) (- 1.0 (get b x) (get b y))) (* (uv_of bb) (get b x)) (* (uv_of c) (get b y))))
    (let alpha (* (get m base_color w) (get (texel (get m textures x) uv 2.0) w)))
    (if ((== mode 1.0) (return (< alpha (get m emissive w)))))
    (return (< alpha (random seed))))

;; Where the ray first meets the triangle, as t and barycentrics, or t of
;; -1.
(fn crossing ((triangle u32) (origin vec3f) (direction vec3f)) (-> vec3f)
    (let a (get (corner triangle 0u) position))
    (let e1 (- (get (corner triangle 1u) position) a))
    (let e2 (- (get (corner triangle 2u) position) a))
    (let p (cross direction e2))
    (let det (dot e1 p))
    (if ((< (abs det) 1e-14) (return (vec3f -1.0))))
    (let inverse (/ 1.0 det))
    (let s (- origin a))
    (let u (* (dot s p) inverse))
    (let q (cross s e1))
    (let v (* (dot direction q) inverse))
    (if ((or (< u 0.0) (< v 0.0) (> (+ u v) 1.0)) (return (vec3f -1.0))))
    (return (vec3f (* (dot e2 q) inverse) u v)))

;; Where the ray enters the box from low to high, or -1 when it misses
;; or enters past `limit`; a NaN misses, since every comparison with it
;; fails. (A miss cannot be `limit` plus one: at 1e30 that is 1e30.)
(fn entering ((low vec3f) (high vec3f) (origin vec3f) (inverse vec3f) (limit f32)) (-> f32)
    (let t0 (* (- low origin) inverse))
    (let t1 (* (- high origin) inverse))
    (let near (max (max (min (get t0 x) (get t1 x)) (min (get t0 y) (get t1 y))) (min (get t0 z) (get t1 z))))
    (let far (min (min (max (get t0 x) (get t1 x)) (max (get t0 y) (get t1 y))) (max (get t0 z) (get t1 z))))
    (if ((not (and (<= near far) (>= far 0.0) (<= near limit))) (return -1.0)))
    (return (max near 0.0)))

;; The hit with the triangle, when it is nearer than the one so far and
;; its cutout does not let the ray through.
(fn tested ((hit (ptr function Hit)) (triangle u32) (origin vec3f) (direction vec3f) (seed (ptr function u32))) (-> bool)
    (let found (crossing triangle origin direction))
    (if ((and (> (get found x) 0.0) (< (get found x) (get (deref hit) t)) (not (passes triangle (get found yz) seed)))
         (= (get (deref hit) t) (get found x))
         (= (get (deref hit) triangle) triangle)
         (= (get (deref hit) barycentric) (get found yz))
         (return true)))
    (return false))

;; The nearest hit before `limit`, or, for occlusion, the first found.
;; Each node holds both children's boxes, so a step tests both: a leaf
;; child's triangle is tested at once, and of two internal children the
;; walk goes on into the nearer and keeps the farther. A walk gives up
;; after 8192 steps, far more than a ray through Sponza needs, so no ray
;; can hold up the device long enough to lose it.
(fn traced ((origin vec3f) (direction vec3f) (limit f32) (occlusion bool) (seed (ptr function u32))) (-> Hit)
    (var (hit Hit))
    (= (get hit t) limit)
    (= (get hit triangle) NONE)
    (let inverse (/ (vec3f 1.0) (select direction (vec3f 1e-30) (== direction (vec3f 0.0)))))
    (var (stack (array u32 64)))
    (var top 0)
    (var node 0u)
    (for ((var steps 0) (< steps 8192) (+= steps 1))
      (let w (at nodes node))
      (var tl (entering (get w left_low) (get w left_high) origin inverse (get hit t)))
      (var go_left (>= tl 0.0))
      (if ((and go_left (!= (bit-and (get w left) TRIANGLE) 0u))
           (= go_left false)
           (if ((and (tested (address-of hit) (bit-xor (get w left) TRIANGLE) origin direction seed) occlusion)
                (return hit)))))
      (let tr (entering (get w right_low) (get w right_high) origin inverse (get hit t)))
      (var go_right (>= tr 0.0))
      (if ((and go_right (!= (bit-and (get w right) TRIANGLE) 0u))
           (= go_right false)
           (if ((and (tested (address-of hit) (bit-xor (get w right) TRIANGLE) origin direction seed) occlusion)
                (return hit)))))
      (= go_left (and go_left (<= tl (get hit t))))
      (= go_right (and go_right (<= tr (get hit t))))
      (if ((and go_left go_right)
           (let near_left (<= tl tr))
           (if ((< top 64) (= (at stack top) (select (get w left) (get w right) near_left)) (+= top 1)))
           (= node (select (get w right) (get w left) near_left)))
          (go_left (= node (get w left)))
          (go_right (= node (get w right)))
          ((== top 0) (break))
          (else (-= top 1) (= node (at stack top)))))
    (return hit))

;; The ray leaves `s` from just above its surface, on the side it goes.
(fn leaving ((s Surface) (direction vec3f)) (-> vec3f)
    (let lift (* 1e-4 (max 1.0 (max (abs (get s position x)) (max (abs (get s position y)) (abs (get s position z)))))))
    (return (+ (get s position) (* (get s geometric) (select (- lift) lift (>= (dot direction (get s geometric)) 0.0))))))

;; ---- Light ----

(fn sky ((direction vec3f)) (-> vec3f)
    (let up (get direction y))
    (if ((< up 0.0) (return (* (get tracing ground xyz) (get tracing ground w)))))
    (return (* (mix (get tracing horizon xyz) (get tracing zenith xyz) (pow up 0.5)) (get tracing zenith w))))

;; ---- Scattering ----

;; An orthonormal frame around n (Duff et al. 2017).
(fn frame_of ((n vec3f)) (-> mat3x3f)
    (let sign (select -1.0 1.0 (>= (get n z) 0.0)))
    (let a (/ -1.0 (+ sign (get n z))))
    (let b (* (get n x) (get n y) a))
    (return (mat3x3f (vec3f (+ 1.0 (* sign (get n x) (get n x) a)) (* sign b) (* (- sign) (get n x)))
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
    (let fresnel (+ (reflectance s) (* (- (vec3f 1.0) (reflectance s)) (pow (- 1.0 (max (dot v h) 0.0)) 5.0))))
    (let specular (/ (* fresnel (ggx alpha (max (dot (get s normal) h) 0.0)) (masking alpha nv) (masking alpha nl))
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
    (let t1 (select (vec3f 1.0 0.0 0.0) (/ (vec3f (- (get vh y)) (get vh x) 0.0) (sqrt lensq)) (> lensq 0.0)))
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
    (return (* frame (vec3f (* radius (cos phi)) (* radius (sin phi)) (sqrt (max 0.0 (- 1.0 (get r x))))))))

;; The sun's light at `s`, through a direction in its disc.
(fn sunlit ((s Surface) (v vec3f) (seed (ptr function u32))) (-> vec3f)
    (let cosine (+ 1.0 (* (random seed) (- (get tracing sun w) 1.0))))
    (let sine (sqrt (max 0.0 (- 1.0 (* cosine cosine)))))
    (let phi (* 2.0 PI (random seed)))
    (let l (* (frame_of (get tracing sun xyz)) (vec3f (* sine (cos phi)) (* sine (sin phi)) cosine)))
    (let f (evaluated s v l))
    (if ((== (dot f f) 0.0) (return (vec3f 0.0))))
    (if ((!= (get (traced (leaving s l) l 1e30 true seed) triangle) NONE) (return (vec3f 0.0))))
    (return (* f (get tracing sun_light xyz))))

;; ---- Paths ----

;; Whether every component is a number and not infinite: a NaN fails both
;; comparisons.
(fn finite3 ((v vec3f)) (-> bool)
    (return (and (all (< (abs v) (vec3f 1e30))) (all (>= (abs v) (vec3f 0.0))))))

(fn path ((start_surface Surface) (view vec3f) (seed (ptr function u32))) (-> vec3f)
    (var s start_surface)
    (var v view)
    (var radiance (get start_surface emission))
    (var weight (vec3f 1.0))
    (var width 0.0)
    (var spread (get tracing view x))
    (let bounces (get tracing frame y))
    (for ((var bounce 0) (< bounce bounces) (+= bounce 1))
      (+= radiance (* weight (sunlit s v seed)))
      (let l (scattered s v seed))
      (let p (density s v l))
      (if ((not (and (> p 1e-6) (finite3 l) (> (dot l (get s geometric)) 0.0))) (break)))
      (*= weight (/ (evaluated s v l) p))
      (if ((not (finite3 weight)) (break)))
      (if ((> bounce 2)
           (let survive (clamp (max (get weight x) (max (get weight y) (get weight z))) 0.05 0.95))
           (if ((> (random seed) survive) (break)))
           (/= weight survive)))
      (let start (leaving s l))
      (let hit (traced start l 1e30 false seed))
      (if ((== (get hit triangle) NONE) (+= radiance (* weight (sky l))) (break)))
      (+= width (* spread (get hit t)))
      (+= spread (* 0.25 (get s roughness)))
      (= v (- l))
      (= s (hit_surface (get hit triangle) (get hit barycentric) v width))
      (= (get s position) (+ start (* l (get hit t))))
      (+= radiance (* weight (get s emission))))
    (return radiance))

(fn (@compute) (@workgroup_size 8 8) trace_main (((@builtin global_invocation_id) id vec3u))
    (let size (textureDimensions depth))
    (if ((or (>= (get id x) (get size x)) (>= (get id y) (get size y))) (return)))
    (let pixel (vec2i (get id xy)))
    (let z (textureLoad depth pixel 0))
    (if ((>= z 1.0)
         (let ndc (- (* (/ (+ (vec2f pixel) 0.5) (vec2f size)) 2.0) 1.0))
         (let far (* (get camera inverse) (vec4f (get ndc x) (- (get ndc y)) 1.0 1.0)))
         (let direction (normalize (- (/ (get far xyz) (get far w)) (get camera eye xyz))))
         (textureStore noisy pixel (vec4f (sky direction) 1.0))
         (return)))
    (var seed (pcg (bit-xor (+ (get id x) (* (get id y) 65521u)) (pcg (u32 (get tracing frame x))))))
    (let s (first_surface pixel z))
    (let view (normalize (- (get camera eye xyz) (get s position))))
    (textureStore noisy pixel (vec4f (path s view (address-of seed)) 1.0)))
