;; Scene descriptions are ordinary immutable Scheme data. They own no GPU
;; handles and can be rebuilt, retained, or discarded independently of a renderer.
(define-library (draw3d scene)
  (export Vertex vertex vertex-position vertex-normal Geometry indexed-geometry
          geometry-identity geometry-vertex-count geometry-index-count geometry-vertex geometry-index
          box-geometry plane-geometry pyramid-geometry Material material material-rgb material-emission
          Model model model-identity model-vertex-count model-index-count model-vertex model-index
          painted-vertex painted-material Node mesh model-instance group moving-group SceneBatch retained-batch translucent-batch phased-batch motion-batch owner-motion-clock reveal-batch dynamic-batch
          BatchReveal no-reveal radial-reveal batch-reveal batch-key batch-state-mask batch-opacity batch-pulse batch-phase batch-duration batch-clock-owner
          batch-dependencies batch-nodes batch-unordered unordered-batch Scene scene batched-scene scene-camera scene-batches
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
    ;; Identities belong to this Wasm module instance. Construction consumes one
    ;; checked ID; failed presentation never rewinds or recycles it.
    (define next-geometry-identity (vector (ann 0 I32)))
    (define (fresh-geometry-identity!)
      (let ((previous (vector-ref next-geometry-identity (ann 0 I64))))
        (when (= previous 2147483647) (unreachable))
        (vector-set! next-geometry-identity (ann 0 I64) (+ previous 1))
        (+ previous 1)))
    (define Geometry
      (datatype ()
        (geometry
         (identity I32 geometry-identity)
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
      (geometry (fresh-geometry-identity!) (copy-vertices vertices)
                (checked-indices indices (i64->i32 (vector-length vertices)))))

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
    (define PaintedVertex
      (datatype ()
        (painted
         (vertex Vertex painted-vertex)
         (material Material painted-material))))
    (define Model
      (datatype ()
        (fixed-model
         (identity I32 model-identity)
         (vertices (Vector PaintedVertex) model-vertices)
         (indices (Vector I32) model-indices))))
    (define (model-vertex-count value) (i64->i32 (vector-length (model-vertices value))))
    (define (model-index-count value) (i64->i32 (vector-length (model-indices value))))
    (define (model-vertex value index) (vector-ref (model-vertices value) (i32->i64 index)))
    (define (model-index value index) (vector-ref (model-indices value) (i32->i64 index)))
    (define Node
      (datatype ()
        (mesh
         (geometry Geometry)
         (material Material)
         (transform Transform))
        (model-instance
         (model Model)
         (transform Transform))
        (group
         (transform Transform)
         (children (List Node)))
        (moving-group
         (previous Transform)
         (current Transform)
         (children (List Node)))))

    ;; ---- Bake a static colored model once, preserving triangle order ----

    ;; The reversed lists are private construction scratch, never frame data.
    (define ModelBuild
      (datatype ()
        (model-build
         (vertices (List PaintedVertex) build-vertices)
         (indices (List I32) build-indices)
         (count I32 build-count))))
    (define (paint-transformed point surface frame)
      (let ((position (transform-point frame (vertex-position point))))
        (unless (and (finite? (vec3-x position)) (finite? (vec3-y position)) (finite? (vec3-z position)))
          (unreachable))
        (painted (vertex position (transform-normal frame (vertex-normal point))) surface)))
    (define (bake-vertices geometry surface frame index values)
      (if (= index (geometry-vertex-count geometry)) values
          (bake-vertices geometry surface frame (+ index 1)
                         (cons (paint-transformed (geometry-vertex geometry index) surface frame) values))))
    (define (bake-indices geometry first index values)
      (if (= index (geometry-index-count geometry)) values
          (bake-indices geometry first (+ index 1) (cons (+ first (geometry-index geometry index)) values))))
    (define (bake-geometry geometry surface frame build)
      (model-build (bake-vertices geometry surface frame 0 (build-vertices build))
                   (bake-indices geometry (build-count build) 0 (build-indices build))
                   (+ (build-count build) (geometry-vertex-count geometry))))
    (define (bake-model-vertices value frame index values)
      (if (= index (model-vertex-count value)) values
          (let ((point (model-vertex value index)))
            (bake-model-vertices value frame (+ index 1)
                                 (cons (paint-transformed (painted-vertex point) (painted-material point) frame) values)))))
    (define (bake-model-indices value first index values)
      (if (= index (model-index-count value)) values
          (bake-model-indices value first (+ index 1) (cons (+ first (model-index value index)) values))))
    (define (bake-model value frame build)
      (model-build (bake-model-vertices value frame 0 (build-vertices build))
                   (bake-model-indices value (build-count build) 0 (build-indices build))
                   (+ (build-count build) (model-vertex-count value))))
    (define (bake-node value parent build)
      (match value
        ((mesh geometry surface local) (bake-geometry geometry surface (compose parent local) build))
        ((model-instance value local) (bake-model value (compose parent local) build))
        ((group local children) (bake-nodes children (compose parent local) build))
        ((moving-group previous current children) (unreachable))))
    (define (bake-nodes values parent build)
      (if (null? values) build
          (bake-nodes (cdr values) parent (bake-node (car values) parent build))))
    ;; A model admits only static subtrees. Independently moving parts remain
    ;; separate instances outside it; presentation never rebuilds its vertices.
    (define (model nodes)
      (let ((build (bake-nodes nodes identity-transform (model-build (empty-list) (empty-list) 0))))
        (fixed-model (fresh-geometry-identity!) (list->vector (reverse (build-vertices build)))
                     (list->vector (reverse (build-indices build))))))

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
         (phase I32 batch-phase)
         (duration I32 batch-duration)
         (clock-owner I32 batch-clock-owner)
         (reveal BatchReveal batch-reveal)
         (unordered Bool batch-unordered)
         (nodes (-> (List Node)) batch-nodes))))
    (define (retained-batch key state-mask dependencies nodes)
      (if (and (>= key 0) (>= state-mask 0) (<= state-mask 3))
          (render-batch key state-mask dependencies 1.0 #f 0 0 0 (no-reveal) #f nodes) (unreachable)))
    (define (translucent-batch key state-mask dependencies opacity pulse nodes)
      (if (and (>= key 0) (>= state-mask 0) (<= state-mask 3) (> opacity 0.0) (< opacity 1.0))
          (render-batch key state-mask dependencies opacity pulse 0 0 0 (no-reveal) #f nodes) (unreachable)))
    ;; Millidegree offsets share the display clock without regenerating meshes.
    ;; Increasing phase along a path makes its bright crest travel forward.
    (define (phased-batch key state-mask dependencies opacity phase nodes)
      (if (and (>= key 0) (>= state-mask 0) (<= state-mask 3) (> opacity 0.0) (< opacity 1.0)
               (>= phase 0) (< phase 360000))
          (render-batch key state-mask dependencies opacity #t phase 0 0 (no-reveal) #f nodes) (unreachable)))
    ;; A motion batch supplies both transformed positions for each current
    ;; vertex. Its duration is measured by the display clock after publication.
    (define (motion-batch key state-mask dependencies duration nodes)
      (if (and (>= key 0) (>= state-mask 0) (<= state-mask 3) (> duration 0))
          (render-batch key state-mask dependencies 1.0 #f 0 duration 0 (no-reveal) #f nodes) (unreachable)))
    ;; Opt in to one display interval per immutable owner snapshot. Camera-only
    ;; instance changes keep that interval; the ordinary motion constructor
    ;; continues to start its clock whenever its geometry changes.
    (define (owner-motion-clock batch owner)
      (unless (and (> (batch-duration batch) 0) (or (= owner 1) (= owner 2))) (unreachable))
      (render-batch (batch-key batch) (batch-state-mask batch) (batch-dependencies batch)
                    (batch-opacity batch) (batch-pulse batch) (batch-phase batch) (batch-duration batch) owner
                    (batch-reveal batch) (batch-unordered batch) (batch-nodes batch)))
    ;; The radius encloses all supplied geometry in world XY. A stable identity
    ;; shares one display-clock transition across batches and camera views.
    ;; Edge zero clips sharply per fragment; a positive width feathers the front.
    (define (reveal-batch batch identity x y radius edge elapsed duration)
      (unless (and (>= identity 0) (finite? x) (finite? y) (finite? radius) (finite? edge)
                   (>= radius 0.0) (>= edge 0.0) (>= elapsed 0) (> duration 0)
                   (or (not (batch-unordered batch)) (= edge 0.0))) (unreachable))
      (render-batch (batch-key batch) (batch-state-mask batch) (batch-dependencies batch)
                    (batch-opacity batch) (batch-pulse batch) (batch-phase batch) (batch-duration batch) (batch-clock-owner batch)
                    (radial-reveal identity x y radius edge elapsed duration) (batch-unordered batch) (batch-nodes batch)))
    ;; Explicit permission to regroup opaque occurrences by fixed model.
    ;; Ordered batches still instance adjacent equal models. Soft transparency
    ;; must retain submission order even when opacity reaches its endpoint.
    (define (unordered-batch batch)
      (unless (and (= (batch-opacity batch) 1.0) (not (batch-pulse batch))
                   (match (batch-reveal batch)
                     ((no-reveal) #t) ((radial-reveal id x y radius edge elapsed duration) (= edge 0.0))))
        (unreachable))
      (render-batch (batch-key batch) (batch-state-mask batch) (batch-dependencies batch)
                    (batch-opacity batch) (batch-pulse batch) (batch-phase batch) (batch-duration batch) (batch-clock-owner batch)
                    (batch-reveal batch) #t (batch-nodes batch)))
    (define (dynamic-batch nodes) (render-batch -1 0 (empty-list) 1.0 #f 0 0 0 (no-reveal) #f nodes))
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
