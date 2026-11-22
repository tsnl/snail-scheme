;; Meshes as tables: one geometry table holding every shape's vertices and
;; indices, an instance table of `Pod` records, and an indirect draw for
;; each shape, starting at its own first instance. A pipeline that draws
;; them takes two vertex buffers, `mesh-buffers`: vertices, then
;; instances. The geometry's buffers are made and written once; a batch's
;; are made when it changes, and destroyed with `release-batch`.
;;
;;   (let* ((geometry (make-geometry))
;;          (batch (upload-batch "terrain"
;;                               (meshes (list (new Pair (first (Box)) (second instance)) ...)))))
;;     (set-pipeline pass pipeline)
;;     (draw-meshes pass geometry batch))
(define-library (snail shell graphics mesh)
  (export
   Mesh
   Box
   Pyramid
   Prism
   Sphere
   Tile
   Tetrahedron
   Octahedron
   Upright
   MeshVertex
   Instance
   Meshes
   meshes
   mesh-buffers
   MeshGeometry
   make-geometry
   MeshBatch
   upload-batch
   release-batch
   draw-meshes)
  (import
   (snail core base)
   (snail shell math)
   (snail shell gpu)
   (snail shell graphics pod))
  (begin

    ;; ---- Shapes ----

    ;; Each stands on y = 0 within the unit cell around the origin: a box,
    ;; a square pyramid, a hexagonal prism, a sphere, a flat tile, a
    ;; tetrahedron, an octahedron, and an upright unit square facing +z.
    (enum Mesh
      (Box)
      (Pyramid)
      (Prism)
      (Sphere)
      (Tile)
      (Tetrahedron)
      (Octahedron)
      (Upright))

    (define all-meshes (→ (List Mesh))
      (list (Box) (Pyramid) (Prism) (Sphere) (Tile) (Tetrahedron) (Octahedron) (Upright)))

    (define (mesh-index (mesh Mesh)) (→ I64)
      (match mesh
        ((Box) 0)
        ((Pyramid) 1)
        ((Prism) 2)
        ((Sphere) 3)
        ((Tile) 4)
        ((Tetrahedron) 5)
        ((Octahedron) 6)
        ((Upright) 7)))

    ;; ---- Geometry ----

    ;; Faces have their own vertices, so shading stays flat; texture
    ;; coordinates project the unit cell onto a face's main plane, top up on
    ;; upright faces.
    (record MeshVertex
      ((position Vec3f)
       (normal Vec3f)
       (uv Vec2f))
      (deriving Pod))

    ;; A shape's vertices and the triangles over them.
    (record Geometry
      ((vertices (List MeshVertex))
       (indices (List I32))))

    (define (point (x F64) (y F64) (z F64)) (→ Vec3f)
      (new Vec3f (x (f64->f32 x)) (y (f64->f32 y)) (z (f64->f32 z))))

    (define (minus (a Vec3f) (b Vec3f)) (→ Vec3f)
      (new Vec3f (x (- (● a x) (● b x))) (y (- (● a y) (● b y))) (z (- (● a z) (● b z)))))

    (define (cross (a Vec3f) (b Vec3f)) (→ Vec3f)
      (new Vec3f
        (x (- (* (● a y) (● b z)) (* (● a z) (● b y))))
        (y (- (* (● a z) (● b x)) (* (● a x) (● b z))))
        (z (- (* (● a x) (● b y)) (* (● a y) (● b x))))))

    ;; A convex face as a fan of triangles, its normal from its first three
    ;; corners.
    (define (face (corners (List Vec3f))) (→ Geometry)
      (let* ((a (list-ref corners 0))
             (normal (cross (minus (list-ref corners 1) a) (minus (list-ref corners 2) a))))
        (new Geometry
          (vertices (map (lambda (corner)
                           (new MeshVertex
                             (position corner)
                             (normal normal)
                             (uv (projected normal corner))))
                         corners))
          (indices (concatenate (map (lambda (i) (list 0 (i64->i32 i) (i64->i32 (+ i 1))))
                                     (list-drop (iota (- (length corners) 1)) 1)))))))

    (define (projected (normal Vec3f) (corner Vec3f)) (→ Vec2f)
      (let ((nx (abs (● normal x))) (ny (abs (● normal y))) (nz (abs (● normal z))))
        (cond
         ((and (>= ny nx) (>= ny nz)) (new Vec2f (x (+ (● corner x) 0.5)) (y (+ (● corner z) 0.5))))
         ((>= nx nz) (new Vec2f (x (+ (● corner z) 0.5)) (y (- 1.0 (● corner y)))))
         (else (new Vec2f (x (+ (● corner x) 0.5)) (y (- 1.0 (● corner y))))))))

    ;; Faces joined into one shape, each face's indices moved past those
    ;; before it.
    (define (joined (faces (List Geometry))) (→ Geometry)
      (fold-left (lambda (shape next)
                   (let ((base (i64->i32 (length (● shape vertices)))))
                     (new Geometry
                       (vertices (append (● shape vertices) (● next vertices)))
                       (indices (append (● shape indices)
                                        (map (lambda (i) (+ i base)) (● next indices)))))))
                 (new Geometry (vertices (Nil)) (indices (Nil)))
                 faces))

    ;; A prism or pyramid of `sides` around y. A square's corners lie on a
    ;; larger circle, so a box spans the unit cell.
    (define (prism (sides I64) (top? Bool)) (→ Geometry)
      (let* ((radius (if (= sides 4) 0.70710678 0.5))
             (ring (lambda (y)
                     (map (lambda (i)
                            (let ((angle (/ (* (* 2.0 pi) (+ (i64->f64 i) 0.5)) (i64->f64 sides))))
                              (point (* radius (cos angle)) y (* radius (sin angle)))))
                          (iota sides))))
             (bottom (ring 0.0))
             (upper (ring 1.0))
             (around (map (lambda (i)
                            (let ((j (modulo (+ i 1) sides)))
                              (face (if top?
                                        (list (list-ref bottom i)
                                              (list-ref upper i)
                                              (list-ref upper j)
                                              (list-ref bottom j))
                                        (list (list-ref bottom i)
                                              (point 0.0 1.0 0.0)
                                              (list-ref bottom j))))))
                          (iota sides))))
        (joined (append around
                        (Cons (face bottom) (if top? (list (face (reverse upper))) (Nil)))))))

    (define (sphere) (→ Geometry)
      (let ((at (lambda (row column)
                  (let ((phi (/ (* pi (i64->f64 row)) 6.0))
                        (theta (/ (* (* 2.0 pi) (i64->f64 column)) 10.0)))
                    (point (* (* 0.5 (sin phi)) (cos theta))
                           (+ 0.5 (* 0.5 (cos phi)))
                           (* (* 0.5 (sin phi)) (sin theta)))))))
        (joined (concatenate
                 (map (lambda (row)
                        (map (lambda (column)
                               (face (distinct (list (at row column)
                                                     (at row (+ column 1))
                                                     (at (+ row 1) (+ column 1))
                                                     (at (+ row 1) column)))))
                             (iota 10)))
                      (iota 6))))))

    ;; A pole's quad has two corners at the pole: its face is a triangle.
    (define (distinct (corners (List Vec3f))) (→ (List Vec3f))
      (fold-left (lambda (kept corner)
                   (if (any? (lambda (other) (near? other corner)) kept)
                       kept
                       (append kept (list corner))))
                 (Nil)
                 corners))

    (define (near? (a Vec3f) (b Vec3f)) (→ Bool)
      (let ((d (minus a b)))
        (< (+ (+ (abs (● d x)) (abs (● d y))) (abs (● d z))) 0.000001)))

    ;; Triangular faces over corners, wound so their normals face outward.
    (define (solid (corners (List Vec3f)) (faces (List (List I64)))) (→ Geometry)
      (joined
       (map (lambda (corner-indices) (face (map (lambda (i) (list-ref corners i)) corner-indices)))
            faces)))

    (define (geometry (mesh Mesh)) (→ Geometry)
      (match mesh
        ((Box) (prism 4 #t))
        ((Pyramid) (prism 4 #f))
        ((Prism) (prism 6 #t))
        ((Sphere) (sphere))
        ((Tile)
         (face (list (point -0.5 0.0 -0.5)
                     (point -0.5 0.0 0.5)
                     (point 0.5 0.0 0.5)
                     (point 0.5 0.0 -0.5))))
        ((Tetrahedron)
         (solid (list (point 0.0 1.0 0.0)
                      (point 0.5 0.0 0.0)
                      (point -0.25 0.0 0.433)
                      (point -0.25 0.0 -0.433))
                (list (list 0 2 1) (list 0 3 2) (list 0 1 3) (list 1 2 3))))
        ((Octahedron)
         (solid (list (point 0.0 1.0 0.0)
                      (point 0.5 0.5 0.0)
                      (point 0.0 0.5 0.5)
                      (point -0.5 0.5 0.0)
                      (point 0.0 0.5 -0.5)
                      (point 0.0 0.0 0.0))
                (list (list 0 2 1)
                      (list 0 3 2)
                      (list 0 4 3)
                      (list 0 1 4)
                      (list 5 1 2)
                      (list 5 2 3)
                      (list 5 3 4)
                      (list 5 4 1))))
        ((Upright)
         (face (list (point -0.5 0.0 0.0)
                     (point 0.5 0.0 0.0)
                     (point 0.5 1.0 0.0)
                     (point -0.5 1.0 0.0))))))

    ;; Where each shape's triangles lie in the geometry table.
    (record Span
      ((first-index I32)
       (count I32)
       (base-vertex I32)))

    (define table (→ (List Geometry)) (map geometry all-meshes))

    (define spans
      (→ (List Span))
      (reverse (● (fold-left (lambda (placed shape)
                               (let ((at (● placed second)))
                                 (new Pair
                                   (first (Cons (new Span
                                                  (first-index (● at first))
                                                  (count (i64->i32 (length (● shape indices))))
                                                  (base-vertex (● at second)))
                                                (● placed first)))
                                   (second (new Pair
                                             (first (+ (● at first)
                                                       (i64->i32 (length (● shape indices)))))
                                             (second (+ (● at second)
                                                        (i64->i32
                                                         (length (● shape vertices))))))))))
                             (new Pair (first (Nil)) (second (new Pair (first 0) (second 0))))
                             table)
                  first)))

    ;; ---- Instances ----

    ;; Where an instance is and its yaw, its scale and glow, its color, where
    ;; it was and 1 when it turns to face the camera, and its metalness and
    ;; roughness. The picking id travels as a 32-bit integer to the G-buffer.
    (record Instance
      ((place Vec4f)
       (scale Vec4f)
       (color Vec4f)
       (from Vec4f)
       (material Vec2f)
       (id I32))
      (deriving Pod))

    ;; What drawIndexedIndirect reads.
    (record DrawArgs
      ((index-count I32)
       (instance-count I32)
       (first-index I32)
       (base-vertex I32)
       (first-instance I32))
      (deriving Pod))

    ;; A batch's instances packed, grouped by shape, and its draws.
    (record Meshes
      ((instances Bytes)
       (draws (List DrawArgs))))

    (define (meshes (items (List (Pair Mesh Instance)))) (→ Meshes)
      (let ((groups (map (lambda (mesh) (of-mesh mesh items)) all-meshes)))
        (new Meshes
          (instances (pack instance-shape (concatenate groups)))
          (draws (draw-list groups spans 0)))))

    (define (of-mesh (mesh Mesh) (items (List (Pair Mesh Instance)))) (→ (List Instance))
      (map (lambda (item) (● item second))
           (filter (lambda (item) (= (mesh-index (● item first)) (mesh-index mesh))) items)))

    (define (draw-list (groups (List (List Instance))) (spans (List Span)) (first I32))
      (→ (List DrawArgs))
      (match (new Pair (first groups) (second spans))
        ((Pair (Cons group groups) (Cons span spans))
         (let ((count (i64->i32 (length group))))
           (Cons (new DrawArgs
                   (index-count (● span count))
                   (instance-count count)
                   (first-index (● span first-index))
                   (base-vertex (● span base-vertex))
                   (first-instance first))
                 (draw-list groups spans (+ first count)))))
        (_ (Nil))))

    ;; ---- Drawing ----

    (define vertex-shape (→ (Shape MeshVertex)) (shape))
    (define instance-shape (→ (Shape Instance)) (shape))
    (define draw-shape (→ (Shape DrawArgs)) (shape))
    (define index-shape (→ (Shape I32)) (shape))

    ;; Vertices at locations 0 to 2, instances from 3.
    (define mesh-buffers
      (→ (List VertexBufferLayout))
      (list (vertex-layout vertex-shape (PerVertex) 0)
            (vertex-layout instance-shape (PerInstance) 3)))

    ;; The shapes' vertices and indices, on the device.
    (record MeshGeometry
      ((vertices GpuBuffer)
       (indices GpuBuffer)))

    (define (make-geometry (gpu Gpu)) (→ MeshGeometry)
      (new MeshGeometry
        (vertices (filled gpu "mesh/geometry/vertices"
                          (pack vertex-shape (concatenate (map (lambda (g) (● g vertices)) table)))
                          (Vertex)))
        (indices (filled gpu "mesh/geometry/indices"
                         (pack index-shape (concatenate (map (lambda (g) (● g indices)) table)))
                         (Index)))))

    ;; A batch on the device: its instances, and its draws with the
    ;; offset of each that has instances.
    (record MeshBatch
      ((instances GpuBuffer)
       (draws GpuBuffer)
       (offsets (List I32))))

    (define (upload-batch (gpu Gpu) (label String) (batch Meshes)) (→ MeshBatch)
      (new MeshBatch
        (instances (filled gpu (string-append label "/instances") (● batch instances) (Vertex)))
        (draws (filled gpu (string-append label "/draws")
                       (pack draw-shape (● batch draws))
                       (Indirect)))
        (offsets (map (lambda (indexed) (i64->i32 (* 20 (● indexed first))))
                      (filter (lambda (indexed) (> (● indexed second instance-count) 0))
                              (map-indexed (lambda (index draw)
                                             (new Pair (first index) (second draw)))
                                           (● batch draws)))))))

    (define (release-batch (gpu Gpu) (batch MeshBatch)) (→ Unit)
      (destroy gpu (BufferObject (● batch instances)))
      (destroy gpu (BufferObject (● batch draws))))

    ;; The batch's draws in `pass`, whose pipeline is set.
    (define (draw-meshes (gpu Gpu) (pass GpuRenderPass) (geometry MeshGeometry) (batch MeshBatch))
      (→ Unit)
      (unless (null? (● batch offsets))
        (set-vertex-buffer gpu pass 0 (● geometry vertices) 0)
        (set-vertex-buffer gpu pass 1 (● batch instances) 0)
        (set-index-buffer gpu pass (● geometry indices) (Uint32Index) 0)
        (for-each (lambda (offset) (draw-indexed-indirect gpu pass (● batch draws) offset))
                  (● batch offsets))))

    ;; A buffer holding `bytes`, at least a word.
    (define (filled (gpu Gpu) (label String) (bytes Bytes) (usage BufferUsage))
      (→ GpuBuffer)
      (let ((buffer (create-buffer gpu (new BufferDescriptor
                                         (label label)
                                         (size (i64->i32 (max 4 (array-length bytes))))
                                         (usage (list usage (CopyDst)))))))
        (write-buffer gpu buffer 0 bytes)
        buffer))

    ))
