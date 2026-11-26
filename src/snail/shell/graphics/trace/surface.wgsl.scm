;; A scene's first hits rasterized into the path tracer's G-buffer: one
;; draw of every triangle's three corners, each corner's vertex read
;; through the scene's indices from its vertex buffer (unpack.wgsl.scm),
;; so a corner knows its triangle; each material from its storage buffer
;; and its textures from layers of one array (scene.sld). `Camera3D`
;; comes from Pod.
;;
;; Targets, in this order so they fit 32 bytes a pixel:
;;   0 normals, rg16float: the shading normal, octahedral, facing the eye;
;;   1 emission, rgba16float, linear RGB and the previous clip-space z;
;;   2 albedo, rgba8unorm-srgb, so 8 bits keep its darks;
;;   3 material, rgba8unorm: metalness, filtered roughness, the water flag and subsurface weight;
;;   4 motion, rg16float, in texture coordinates from the last frame;
;;   5 triangle, r32uint: the triangle drawn there.
;; Depth is depth32float. The tracer places each pixel by its depth, then
;; onto the plane of its triangle, whose geometric normal it takes too
;; (path.wgsl.scm).
;;
;; A texture's colors are sRGB; its data, normals and metal-roughness,
;; are linear. A masked material discards below its cutoff. A blended one
;; draws only in the blended layer (`blended_fragment`), a second G-buffer of the
;; same targets whose depth starts as the first hits': the nearest
;; blended surface in front of them, its alpha in the albedo's, which the
;; tracer lights as it lights the first hits and blends over them
;; (render.sld). Its motion is its own, so each is filtered with its own.
(struct Vertex
        (position vec3f)
        (u f32)
        (normal vec3f)
        (v f32)
        (tangent vec4f)
        (material u32)
        (dx f32)
        (dy f32)
        (dz f32))

((var uniform) (@group 0) (@binding 0) (camera Camera3D))

((var storage read) (@group 0) (@binding 1) (vertices (array Vertex)))

((var storage read) (@group 0) (@binding 2) (materials (array SurfaceMaterial)))

(var (@group 0) (@binding 3) (layers (texture_2d_array f32)))

(var (@group 0) (@binding 4) (repeat sampler))

((var storage read) (@group 0) (@binding 5) (indices (array u32)))

(struct Varying
        ((@builtin position) position vec4f)
        ((@location 0) world vec3f)
        ((@location 1) normal vec3f)
        ((@location 2) uv vec2f)
        ((@location 3) tangent vec4f)
        ((@location 4) (@interpolate flat) material u32)
        ((@location 5) clip_now vec4f)
        ((@location 6) clip_before vec4f)
        ((@location 7) (@interpolate flat) triangle u32))

;; Corner `index` of the draw is corner index mod 3 of triangle index / 3.
(fn (@vertex) surface_vertex (((@builtin vertex_index) index u32)) (-> Varying)
    (let vertex (at vertices (at indices index)))
    (var (out Varying))
    (= (get out triangle) (/ index 3u))
    (= (get out position) (* (get camera view_projection) (vec4f (get vertex position) 1.0)))
    (= (get out world) (get vertex position))
    (= (get out normal) (get vertex normal))
    (= (get out uv) (vec2f (get vertex u) (get vertex v)))
    (= (get out tangent) (get vertex tangent))
    (= (get out material) (get vertex material))
    (= (get out clip_now) (get out position))
    (let before (+ (get vertex position) (vec3f (get vertex dx) (get vertex dy) (get vertex dz))))
    (= (get out clip_before) (* (get camera previous) (vec4f before 1.0)))
    (return out))

(struct Targets
        ((@location 0) normals vec2f)
        ((@location 1) emission vec4f)
        ((@location 2) albedo vec4f)
        ((@location 3) material vec4f)
        ((@location 4) motion vec2f)
        ((@location 5) triangle u32))

(fn decoded ((c vec3f)) (-> vec3f)
    (return (select (pow (/ (+ c 0.055) 1.055) (vec3f 2.4)) (/ c 12.92) (<= c (vec3f 0.04045)))))

;; The screen derivatives of position and uv, taken first, where control
;; flow is uniform, so textures sample by gradient wherever they are read.
(struct Footprint
        (uv vec2f)
        (uv_x vec2f)
        (uv_y vec2f)
        (p_x vec3f)
        (p_y vec3f))

;; A texture's texel, or white when the layer is -1.
(fn texel ((layer i32) (f Footprint)) (-> vec4f)
    (if ((< layer 0) (return (vec4f 1.0))))
    (return (textureSampleGrad layers repeat (get f uv) layer (get f uv_x) (get f uv_y))))

;; A unit vector folded onto the octahedron, then flattened to a square.
(fn octahedral ((n vec3f)) (-> vec2f)
    (let p (/ (get n xy) (+ (abs (get n x)) (abs (get n y)) (abs (get n z)))))
    (if ((< (get n z) 0.0)
         (return
          (* (- 1.0 (abs (get p yx))) (select (vec2f -1.0) (vec2f 1.0) (>= p (vec2f 0.0)))))))
    (return p))

;; The normal map's normal in the frame of `normal` and the tangent, or,
;; without a tangent, a frame from the derivatives of position and uv, as
;; Schüler's cotangent frame.
(fn mapped ((m SurfaceMaterial) (f Footprint) (tangent vec4f) (normal vec3f)) (-> vec3f)
    (let layer (get m textures z))
    (if ((< layer 0) (return normal)))
    (let t (- (* 2.0 (get (texel layer f) xyz)) 1.0))
    (let local (normalize (vec3f (* (get t xy) (get m factors z)) (get t z))))
    (if ((> (dot (get tangent xyz) (get tangent xyz)) 0.0)
         (let along (normalize (- (get tangent xyz) (* normal (dot normal (get tangent xyz))))))
         (let across (* (cross normal along) (get tangent w)))
         (return (normalize
                  (+ (* along (get local x)) (* across (get local y)) (* normal (get local z)))))))
    (let r1 (cross (get f p_y) normal))
    (let r2 (cross normal (get f p_x)))
    (let along (+ (* r1 (get f uv_x x)) (* r2 (get f uv_y x))))
    (let across (+ (* r1 (get f uv_x y)) (* r2 (get f uv_y y))))
    (let scale (inverseSqrt (max (max (dot along along) (dot across across)) 1e-20)))
    (return (normalize (+ (* along (* scale (get local x)))
                          (* across (* scale (get local y)))
                          (* normal (get local z))))))

;; The footprint at a fragment, taken where control flow is uniform.
(fn footprint ((in Varying)) (-> Footprint)
    (var (f Footprint))
    (= (get f uv) (get in uv))
    (= (get f uv_x) (dpdx (get in uv)))
    (= (get f uv_y) (dpdy (get in uv)))
    (= (get f p_x) (dpdx (get in world)))
    (= (get f p_y) (dpdy (get in world)))
    (return f))

;; An opaque material's first hit. No texel of it leaves the pixel to what
;; is behind, so the depth test can run before the shader does: the
;; tracer draws opaque runs of triangles with this, and the rest with
;; `surface_fragment`.
(fn (@fragment) opaque_fragment ((in Varying)) (-> Targets)
    (let f (footprint in))
    (let m (at materials (get in material)))
    (return (drawn in f m (texel (get m textures x) f) 1.0)))

;; A masked material's first hit; one below its cutoff, and every blended
;; one, leave it to what is behind.
(fn (@fragment) surface_fragment ((in Varying)) (-> Targets)
    (let f (footprint in))
    (let m (at materials (get in material)))
    (let base (texel (get m textures x) f))
    (let alpha (* (get m base_color w) (get base w)))
    (if ((and (== (get m factors w) 1.0) (< alpha (get m emissive w))) (discard))
        ((== (get m factors w) 2.0) (discard)))
    (return (drawn in f m base 1.0)))

;; A blended material's hit, for the blended layer: the depth test keeps the
;; nearest in front of the first hits. A texel it barely covers is none,
;; so it hides nothing behind it.
(fn (@fragment) blended_fragment ((in Varying)) (-> Targets)
    (let f (footprint in))
    (let m (at materials (get in material)))
    (let base (texel (get m textures x) f))
    (let alpha (* (get m base_color w) (get base w)))
    (if ((or (!= (get m factors w) 2.0) (< alpha (/ 1.0 255.0))) (discard)))
    (return (drawn in f m base alpha)))

;; What a hit writes, its albedo's alpha `alpha`.
(fn drawn ((in Varying) (f Footprint) (m SurfaceMaterial) (base vec4f) (alpha f32)) (-> Targets)
    (let toward (normalize (- (get camera eye xyz) (get in world))))
    (var geometric (normalize (cross (get f p_y) (get f p_x))))
    (if ((< (dot geometric toward) 0.0) (= geometric (- geometric))))
    (var normal (get in normal))
    (if ((< (dot normal normal) 1e-12) (= normal geometric)))
    (= normal (normalize normal))
    (if ((< (dot normal geometric) 0.0) (= normal (- normal))))
    (let metal_rough (texel (get m textures y) f))
    (var rough (* (get m factors y) (get metal_rough y)))
    (let water (!= (get m flags y) 0))
    (if (water
         (let waves (water_surface (get in world) geometric (get camera scene_time)
                                   (mat2x2f (get f p_x xz) (get f p_y xz)) rough))
         (= normal (get waves xyz))
         (= rough (get waves w)))
        (else (= normal (mapped m f (get in tangent) normal))))
    (var (out Targets))
    (= (get out normals) (octahedral normal))
    (= (get out emission)
       (vec4f (* (get m emissive xyz) (decoded (get (texel (get m textures w) f) xyz)))
              (get in clip_before z)))
    (= (get out albedo) (vec4f (* (get m base_color xyz) (decoded (get base xyz))) alpha))
    (= (get out material)
       (vec4f (* (get m factors x) (get metal_rough z))
              rough
              (select 0.0 1.0 water)
              (/ (f32 (get m flags z)) 255.0)))
    (let now (/ (get in clip_now xy) (get in clip_now w)))
    (let before (/ (get in clip_before xy) (get in clip_before w)))
    (= (get out motion) (* (- now before) (vec2f 0.5 -0.5)))
    (= (get out triangle) (get in triangle))
    (return out))
