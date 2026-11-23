;; Extend an imported model with the same unit shapes the raster games use.
;; Their vertex and index data is uploaded once per shape. Each item adds a
;; placement and a matte material, retaining the imported texture indices.
(define-library (snail shell game scenery)
  (export with-shapes item-pose)
  (import
   (snail core base)
   (snail shell math)
   (snail shell app)
   (snail shell graphics gltf)
   (only (snail shell graphics mesh) MeshVertex geometry all-meshes mesh-index)
   (snail shell graphics pod)
   (only (snail shell graphics trace scene) ObjectPose))
  (begin
    (define vertices (→ (Shape MeshVertex)) (shape))
    (define indices (→ (Shape I32)) (shape))
    (record Shapes
      ((end I64)
       (buffers (List Buffer))
       (primitives (List Primitive))))

    (define (attribute (at I64) (step I64) (width I64) (component I64) (count I64)) (→ Attribute)
      (new Attribute
        (offset at)
        (stride step)
        (width width)
        (component component)
        (normalized #f)
        (count count)))

    (define (mesh-data (kit Shapes) (mesh Mesh)) (→ Shapes)
      (let* ((g (geometry mesh)) (v (pack vertices (● g vertices))) (i (pack indices (● g indices)))
             (bytes (array-append v i)) (start (● kit end)) (n (length (● g vertices)))
             (norm (● (list-ref (● vertices layout fields) 1) offset))
             (p (new Primitive (positions (attribute start (stride vertices) 3 5126 n))
                     (normals (Some (attribute (+ start norm) (stride vertices) 3 5126 n)))
                     (uvs (None)) (tangents (None)) (joints (None)) (weights (None))
                     (indices
                      (Some (attribute (+ start (array-length v)) 4 1 5125 (length (● g indices)))))
                     (material 0) (low (list -0.5 0.0 -0.5)) (high (list 0.5 1.0 0.5)))))
        (new Shapes (end (+ start (array-length bytes)))
             (buffers (Cons (new Buffer
                              (source (DataSource bytes))
                              (start start)
                              (length (array-length bytes)))
                            (● kit buffers)))
             (primitives (Cons p (● kit primitives))))))

    (define (linear (byte I32)) (→ F64)
      (let ((s (/ (i32->f64 byte) 255.0)))
        (if (<= s 0.04045) (/ s 12.92) (expt (/ (+ s 0.055) 1.055) 2.4))))

    (define (paint (part Item)) (→ Material)
      (let* ((c (● part color))
             (color (map (lambda (k) (linear (remainder (quotient c k) 256))) (list 65536 256 1))))
        (new Material (base-color (append color (list 1.0))) (metallic 0.0) (roughness 0.78)
             (base-texture -1) (metal-rough-texture -1) (normal-texture -1) (normal-scale 1.0)
             (emissive (map (lambda (v) (* v (f32->f64 (● part glow)))) color))
             (emissive-texture -1) (alpha 0) (alpha-cutoff 0.5) (double-sided #t))))

    (define (item-pose (part Item)) (→ ObjectPose)
      (let ((p (● part position)) (s (● part scale)) (angle (f32->f64 (● part yaw))))
        (new ObjectPose
          (place (new Vec4f (x (● p x)) (y (● p y)) (z (● p z)) (w (f64->f32 (cos angle)))))
          (size (new Vec4f (x (● s x)) (y (● s y)) (z (● s z)) (w (f64->f32 (sin angle))))))))

    (define (matrix (part Item)) (→ (List F64))
      (let* ((pose (item-pose part)) (s (● pose size)) (p (● pose place))
             (c (● p w)) (a (● s w)))
        (map f32->f64 (list (* c (● s x)) 0.0 (negate (* a (● s x))) 0.0
                            0.0 (● s y) 0.0 0.0
                            (* a (● s z)) 0.0 (* c (● s z)) 0.0
                            (● p x) (● p y) (● p z) 1.0))))

    (define (with-shapes (source Gltf) (parts (List Item))) (→ Gltf)
      (let* ((kit (fold-left mesh-data
                             (new Shapes (end (● source size)) (buffers (Nil)) (primitives (Nil)))
                             all-meshes))
             (shapes (list->array (reverse (● kit primitives))))
             (materials (scene-materials source))
             (first (length materials))
             (placed (map-indexed (lambda (i p)
                                    (new Placed (node -1) (matrix (matrix p))
                                         (primitive (Primitive-material-set
                                                     (array-ref shapes (mesh-index (● p mesh)))
                                                     (+ first i)))))
                                  parts)))
        (new Gltf (buffers (append (● source buffers) (reverse (● kit buffers)))) (size (● kit end))
             (images (● source images)) (materials (append materials (map paint parts)))
             (placed (append (● source placed) placed)))))))
