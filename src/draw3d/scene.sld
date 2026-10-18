;; Scene descriptions are ordinary immutable Scheme data. They own no GPU
;; handles and can be rebuilt, retained, or discarded independently of a renderer.
(define-library (draw3d scene)
  (export Vertex vertex vertex-position vertex-normal Geometry indexed-geometry
          geometry-vertex-count geometry-index-count geometry-vertex geometry-index
          box-geometry plane-geometry pyramid-geometry Material material material-rgb material-emission
          Node mesh group moving-group SceneBatch retained-batch translucent-batch motion-batch reveal-batch dynamic-batch
          BatchReveal no-reveal radial-reveal batch-reveal batch-key batch-state-mask batch-opacity batch-pulse batch-duration
          batch-dependencies batch-nodes Scene scene batched-scene scene-camera scene-batches
          scene-light scene-ambient scene-background
          DirectionalLight directional-light light-direction light-intensity test-scene)
  (import
   (scheme base)
   (scheme immutable)
   (draw3d math)
   (only (lofi base) vector-copy list->vector i32->i64 i64->i32 unreachable)
   (only (lofi core) datatype match ann -> I32 I64 F64))
  (begin

    ;; ---- Indexed geometry establishes finite vertices and in-range triangles ----

    (define Vertex
      (datatype ()
        (vertex
         (position Vec3 vertex-position)
         (normal Vec3 vertex-normal))))
    (define Geometry
      (datatype ()
        (geometry
         (vertices (Vector Vertex) geometry-vertices)
         (indices (Vector I32) geometry-indices))))
    (define (geometry-vertex-count value) (i64->i32 (vector-length (geometry-vertices value))))
    (define (geometry-index-count value) (i64->i32 (vector-length (geometry-indices value))))
    (define (geometry-vertex value index) (vector-ref (geometry-vertices value) (i32->i64 index)))
    (define (geometry-index value index) (vector-ref (geometry-indices value) (i32->i64 index)))
    (define (copy-vertices vertices)
      (let ((copy (vector-copy vertices)))
        (let loop ((index 0))
          (when (< (i32->i64 index) (vector-length copy))
            (let* ((v (vector-ref copy (i32->i64 index))) (p (vertex-position v)))
              (unless (and (finite? (vec3-x p)) (finite? (vec3-y p)) (finite? (vec3-z p))) (unreachable))
              (vector-set! copy (i32->i64 index) (vertex p (normalize (vertex-normal v)))))
            (loop (+ index 1)))) copy))
    (define (checked-indices indices count)
      (let ((copy (vector-copy indices)))
        (unless (= (remainder (i64->i32 (vector-length copy)) 3) 0) (unreachable))
        (let loop ((index 0))
          (when (< (i32->i64 index) (vector-length copy))
            (let ((v (vector-ref copy (i32->i64 index))))
              (unless (and (>= v 0) (< v count)) (unreachable)))
            (loop (+ index 1)))) copy))
    (define (indexed-geometry vertices indices)
      (geometry (copy-vertices vertices) (checked-indices indices (i64->i32 (vector-length vertices)))))

    ;; ---- Small reusable primitives centered at the origin ----

    (define (face normal a b c d) (list (vertex a normal) (vertex b normal) (vertex c normal) (vertex d normal)))
    (define (face-indices offset)
      (list offset (+ offset 1) (+ offset 2) offset (+ offset 2) (+ offset 3)))
    (define box-geometry
      (let ((a (vec3 -0.5 -0.5 -0.5)) (b (vec3 0.5 -0.5 -0.5))
            (c (vec3 0.5 0.5 -0.5)) (d (vec3 -0.5 0.5 -0.5))
            (e (vec3 -0.5 -0.5 0.5)) (f (vec3 0.5 -0.5 0.5))
            (g (vec3 0.5 0.5 0.5)) (h (vec3 -0.5 0.5 0.5)))
        (indexed-geometry
         (list->vector (append (face (vec3 0.0 0.0 1.0) e f g h)
                               (append (face (vec3 0.0 -1.0 0.0) a b f e)
                                       (append (face (vec3 1.0 0.0 0.0) b c g f)
                                               (append (face (vec3 0.0 1.0 0.0) c d h g)
                                                       (append (face (vec3 -1.0 0.0 0.0) d a e h)
                                                               (face (vec3 0.0 0.0 -1.0) d c b a)))))))
         (list->vector (append (face-indices 0) (append (face-indices 4) (append (face-indices 8)
                                                                                 (append (face-indices 12) (append (face-indices 16) (face-indices 20))))))))))
    (define plane-geometry
      (indexed-geometry
       (list->vector (face (vec3 0.0 0.0 1.0) (vec3 -0.5 -0.5 0.0) (vec3 0.5 -0.5 0.0)
                           (vec3 0.5 0.5 0.0) (vec3 -0.5 0.5 0.0)))
       (list->vector (face-indices 0))))
    (define (triangle a b c)
      (let ((normal (normalize (cross (v- b a) (v- c a)))))
        (list (vertex a normal) (vertex b normal) (vertex c normal))))
    (define pyramid-geometry
      (let ((a (vec3 -0.5 -0.5 -0.5)) (b (vec3 0.5 -0.5 -0.5))
            (c (vec3 0.5 0.5 -0.5)) (d (vec3 -0.5 0.5 -0.5)) (top (vec3 0.0 0.0 0.5)))
        (indexed-geometry
         (list->vector (append (triangle a b top) (append (triangle b c top)
                                                          (append (triangle c d top) (append (triangle d a top)
                                                                                             (face (vec3 0.0 0.0 -1.0) d c b a))))))
         (vector 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 12 14 15))))

    ;; ---- Materials, hierarchy, lights and complete frame descriptions ----

    (define Material
      (datatype ()
        (surface
         (rgb I32 material-rgb)
         (emission F64 material-emission))))
    ;; Emission blends from Lambert lighting (0) to an unlit marker (1).
    (define (material rgb emission)
      (if (and (>= rgb 0) (<= rgb 16777215) (>= emission 0.0) (<= emission 1.0))
          (surface rgb emission) (unreachable)))
    (define Node
      (datatype ()
        (mesh
         (geometry Geometry)
         (material Material)
         (transform Transform))
        (group
         (transform Transform)
         (children (List Node)))
        (moving-group
         (previous Transform)
         (current Transform)
         (children (List Node)))))
    (define DirectionalLight
      (datatype ()
        (sun
         (direction Vec3 light-direction)
         (intensity F64 light-intensity))))
    ;; Direction points toward the light, in world space.
    (define (directional-light direction intensity)
      (if (and (finite? intensity) (>= intensity 0.0))
          (sun (normalize direction) intensity) (unreachable)))
    ;; A retained batch is a pure, lazy declaration. State-mask bit zero names
    ;; match state and bit one names client state. The host may reuse geometry
    ;; only while those immutable snapshots and every scalar dependency match.
    (define BatchReveal
      (datatype ()
        (no-reveal)
        (radial-reveal
         (identity I32)
         (x F64)
         (y F64)
         (radius F64)
         (edge F64)
         (elapsed I32)
         (duration I32))))
    (define SceneBatch
      (datatype ()
        (render-batch
         (key I32 batch-key)
         (state-mask I32 batch-state-mask)
         (dependencies (List I32) batch-dependencies)
         (opacity F64 batch-opacity)
         (pulse Bool batch-pulse)
         (duration I32 batch-duration)
         (reveal BatchReveal batch-reveal)
         (nodes (-> (List Node)) batch-nodes))))
    (define (retained-batch key state-mask dependencies nodes)
      (if (and (>= key 0) (>= state-mask 0) (<= state-mask 3))
          (render-batch key state-mask dependencies 1.0 #f 0 (no-reveal) nodes) (unreachable)))
    (define (translucent-batch key state-mask dependencies opacity pulse nodes)
      (if (and (>= key 0) (>= state-mask 0) (<= state-mask 3) (> opacity 0.0) (< opacity 1.0))
          (render-batch key state-mask dependencies opacity pulse 0 (no-reveal) nodes) (unreachable)))
    ;; A motion batch supplies both transformed positions for each current
    ;; vertex. Its duration is measured by the display clock after publication.
    (define (motion-batch key state-mask dependencies duration nodes)
      (if (and (>= key 0) (>= state-mask 0) (<= state-mask 3) (> duration 0))
          (render-batch key state-mask dependencies 1.0 #f duration (no-reveal) nodes) (unreachable)))
    ;; The radius encloses all supplied geometry in world XY. A stable identity
    ;; shares one display-clock transition across batches and camera views.
    (define (reveal-batch batch identity x y radius edge elapsed duration)
      (unless (and (>= identity 0) (finite? x) (finite? y) (finite? radius) (finite? edge)
                   (>= radius 0.0) (> edge 0.0) (>= elapsed 0) (> duration 0)) (unreachable))
      (render-batch (batch-key batch) (batch-state-mask batch) (batch-dependencies batch)
                    (batch-opacity batch) (batch-pulse batch) (batch-duration batch)
                    (radial-reveal identity x y radius edge elapsed duration) (batch-nodes batch)))
    (define (dynamic-batch nodes) (render-batch -1 0 (empty-list) 1.0 #f 0 (no-reveal) nodes))
    (define Scene
      (datatype ()
        (scene-description
         (camera Camera scene-camera)
         (batches (List SceneBatch) scene-batches)
         (light DirectionalLight scene-light)
         (ambient Vec3 scene-ambient)
         (background I32 scene-background))))
    (define (batched-scene camera batches light ambient background)
      (scene-description camera batches light ambient background))
    (define (scene camera nodes light ambient background)
      (batched-scene camera (list (dynamic-batch (lambda () nodes))) light ambient background))

    ;; ---- Tests ----

    (define (test-scene)
      (let* ((vertices (vector (vertex (vec3 0.0 0.0 0.0) (vec3 0.0 0.0 2.0))
                               (vertex (vec3 1.0 0.0 0.0) (vec3 0.0 0.0 2.0))
                               (vertex (vec3 0.0 1.0 0.0) (vec3 0.0 0.0 2.0))))
             (indices (vector 0 1 2)) (shape (indexed-geometry vertices indices)))
        (vector-set! indices (ann 0 I64) (ann 99 I32))
        (vector-set! vertices (ann 0 I64) (vertex (vec3 99.0 0.0 0.0) (vec3 0.0 0.0 1.0)))
        (and (= (geometry-index shape 0) 0) (= (geometry-vertex-count box-geometry) 24)
             (= (geometry-index-count box-geometry) 36)
             (= (vec3-x (vertex-position (geometry-vertex shape 0))) 0.0)
             (= (vec3-z (vertex-normal (geometry-vertex shape 0))) 1.0))))))
