;; A released RadFoam in COLMAP world coordinates. Edges in offsets[i..i+1]
;; are the Delaunay neighbors of site i. Adjacent differences are cached at
;; the same half precision as the reference CUDA traversal.
((var storage read) (@group 0) (@binding 0) (sites (array vec4f)))
((var storage read) (@group 0) (@binding 1) (offsets (array u32)))
((var storage read) (@group 0) (@binding 2) (neighbors (array u32)))
((var storage read) (@group 0) (@binding 3) (harmonics (array f32)))
((var storage read_write) (@group 0) (@binding 4) (deltas (array vec2u)))
((var uniform) (@group 0) (@binding 5) (camera CameraUniform))
((var storage read_write) (@group 0) (@binding 6) (first_site u32))
((var storage read_write) (@group 0) (@binding 7) (pixels (array vec4f)))

(fn (@compute) (@workgroup_size 64) cache_faces (((@builtin global_invocation_id) gid vec3u))
    (let i (+ (get gid x) (* (get gid y) 65535u 64u)))
    (if ((>= i (arrayLength (address-of sites))) (return)))
    (let p (get (at sites i) xyz))
    (for ((var e (at offsets i)) (< e (at offsets (+ i 1u))) (+= e 1u))
         (let d (- (get (at sites (at neighbors e)) xyz) p))
         (= (at deltas e)
            (vec2u (pack2x16float (get d xy)) (pack2x16float (vec2f (get d z) 0.0))))))

(fn eye_distance ((i u32)) (-> f32)
    (let delta (- (get (at sites i) xyz) (get camera eye xyz)))
    (return (dot delta delta)))

;; Outside a Voronoi cell the eye violates at least one of its face
;; inequalities. Its Delaunay neighbor across that face is strictly closer.
;; All pinhole rays start in the same cell.
(fn (@compute) (@workgroup_size 1) locate_eye ()
    (var i 0u)
    (var best (eye_distance i))
    (loop
     (var next i)
     (for ((var e (at offsets i)) (< e (at offsets (+ i 1u))) (+= e 1u))
          (let j (at neighbors e))
          (let dist (eye_distance j))
          (if ((< dist best) (= best dist) (= next j))))
     (if ((== i next) (break)))
     (= i next))
    (= first_site i))

(struct Hit (edge u32) (distance f32))

(fn cell_exit ((i u32) (p vec3f) (dir vec3f)) (-> Hit)
    (var hit (Hit 0xffffffffu 3.4028234e38))
    (for ((var e (at offsets i)) (< e (at offsets (+ i 1u))) (+= e 1u))
         (let packed (at deltas e))
         (let n (vec3f (unpack2x16float (get packed x)) (get (unpack2x16float (get packed y)) x)))
         (let speed (dot n dir))
         (if ((> speed 0.0)
              (let middle (+ p (* 0.5 n)))
              (let t (/ (dot (- middle (get camera eye xyz)) n) speed))
              (if ((< t (get hit distance)) (= hit (Hit e t)))))))
    (return hit))

;; The reference integrates only finite intervals, then composites the
;; remaining transmittance over white. It may cross a zero-length interval
;; at a tied face. Its traversal budget and opacity cutoff are per ray.
(fn trace ((dir vec3f)) (-> vec3f)
    (var i first_site)
    (var near 0.0)
    (var trans 1.0)
    (var rgb (vec3f 0.0))
    (for ((var step 0u) (< step 1024u) (+= step 1u))
         (let site (at sites i))
         (let hit (cell_exit i (get site xyz) dir))
         (if ((== (get hit edge) 0xffffffffu) (break)))
         (let far (max near (get hit distance)))
         (let alpha (- 1.0 (exp (* (- (get site w)) (- far near)))))
         (if ((and (> alpha 0.0) (> (get site w) 0.000001))
              (+= rgb (* trans alpha (shade i dir)))))
         (*= trans (- 1.0 alpha))
         (if ((<= trans 0.001) (break)))
         (= near far)
         (= i (at neighbors (get hit edge))))
    (return (clamp (+ rgb trans) (vec3f 0.0) (vec3f 1.0))))

(fn (@compute) (@workgroup_size 8 8) render_checkpoint (((@builtin global_invocation_id) gid vec3u))
    (let xy (get gid xy))
    (let frame (vec2u (get camera image zw)))
    (if ((any (>= xy frame)) (return)))
    (let source (vec2u (get camera image xy)))
    (let pixel (vec2f (/ (* (+ (* xy 2u) (vec2u 1u)) source) (* frame 2u))))
    (let dir (normalize (+ (get camera corner xyz) (* (get pixel x) (get camera dx xyz))
                           (* (get pixel y) (get camera dy xyz)))))
    (= (at pixels (+ (get xy x) (* (get xy y) (get frame x)))) (vec4f (trace dir) 1.0)))
