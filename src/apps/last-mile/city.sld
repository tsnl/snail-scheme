;; Each sector is uploaded once and uses the same city material slots.
(define-library (apps last-mile city)
  (export Streets empty-streets load-streets! city-materials nearby-geometry)
  (import
   (snail core base)
   (snail core table)
   (prefix (snail shell graphics renderer) api:)
   (snail shell little-endian)
   (snail shell graphics gltf)
   (snail shell graphics forward lights)
   (only (snail shell graphics pod) Vec3f)
   (snail shell game atlas)
   (snail shell game terrain))
  (begin
    (record Streets
      ((handles (Table api:GeometryHandle))
       (lights (List Punctual))))
    (define (empty-streets) (→ Streets)
      (new Streets (handles (empty-table)) (lights (Nil))))
    (define (paint (r F64) (g F64) (b F64) (tex I64) (glow F64)) (→ Material)
      (new Material (base-color (list r g b 1.0)) (base-texture tex) (metallic 0.0) (roughness 0.86)
           (metal-rough-texture -1) (normal-texture -1) (normal-scale 1.0)
           (emissive (list (* r glow) (* g glow) (* b glow))) (emissive-texture -1)
           (alpha (OpaqueMaterial))
           (occlusion-texture -1) (occlusion-strength 1.0) (ground-layer #f) (subsurface 0.0)
           (diffuse-transmission 0.0)
           (fiber-anisotropy 0.0)
           (alpha-cutoff 0.5)
           (double-sided #t)
           (water #f)))
    (define paints (→ (List Material)) (list
                                        (paint 0.115 0.13 0.15 -1 0.0)
                                        (paint 0.54 0.5 0.43 -1 0.0)
                                        (paint 0.32 0.36 0.23 -1 0.0)
                                        (paint 0.2 0.38 0.19 -1 0.0)
                                        (new Material
                                          (base-color (list 0.015 0.049 0.041 1.0))
                                          (base-texture -1)
                                          (metallic 0.0)
                                          (roughness 0.13)
                                          (metal-rough-texture -1)
                                          (normal-texture -1)
                                          (normal-scale 1.0)
                                          (emissive (list 0.0 0.0 0.0))
                                          (emissive-texture -1)
                                          (alpha (OpaqueMaterial))
                                          (occlusion-texture -1)
                                          (occlusion-strength 1.0)
                                          (ground-layer #f)
                                          (subsurface 0.0)
                                          (diffuse-transmission 0.0) (fiber-anisotropy 0.0)
                                          (alpha-cutoff 0.5)
                                          (double-sided #t)
                                          (water #t))
                                        (paint 0.91 0.69 0.25 -1 0.0)
                                        (paint 0.26 0.28 0.29 -1 0.0)
                                        (paint 0.23 0.16 0.1 -1 0.0)
                                        (paint 0.19 0.38 0.22 -1 0.0)
                                        (paint 0.11 0.28 0.23 -1 0.0)
                                        (paint 0.15 0.3 0.36 -1 0.0)
                                        (paint 0.97 0.82 0.51 -1 2.8)
                                        (paint 0.75 0.71 0.58 -1 0.0)
                                        (paint 0.12 0.14 0.15 -1 0.0)
                                        (paint 0.55 0.35 0.19 -1 0.0)
                                        (paint 0.63 0.19 0.11 -1 0.0)
                                        (paint 0.12 0.39 0.36 -1 0.0)
                                        (paint 0.78 0.54 0.18 -1 0.0)
                                        (paint 0.88 0.77 0.64 0 0.0)
                                        (paint 0.68 0.79 0.76 1 0.0)
                                        (paint 0.85 0.67 0.57 2 0.0)
                                        (paint 0.78 0.77 0.72 3 0.0)
                                        (paint 0.71 0.75 0.82 4 0.0)))
    (define (attribute (at I64) (step I64) (width I64) (format I64) (n I64)) (→ Attribute)
      (new Attribute
        (offset at)
        (stride step)
        (width width)
        (component format)
        (normalized #f)
        (count n)))
    (define (placed (d Bytes) (k I64) (base I64) (matrix (List F64))) (→ Placed)
      (let* ((h (+ 4 (* 20 k))) (mat (u32 d h)) (nv (u32 d (+ h 4))) (ni (u32 d (+ h 8)))
             (v (+ base (u32 d (+ h 12)))) (idx (+ base (u32 d (+ h 16)))))
        (new Placed (node -1) (matrix matrix)
             (primitive (new Primitive (positions (attribute v 8 3 5123 nv)) (normals (None))
                             (uvs (if (>= mat 18) (Some (attribute (+ v 6) 8 2 5121 nv)) (None)))
                             (tangents (None))
                             (joints (None))
                             (weights (None))
                             (indices (Some (attribute idx 4 1 5125 ni)))
                             (material mat)
                             (low (list 0.0 0.0 0.0))
                             (high (list 25600.0 35000.0 25600.0)))))))
    (define (sector-parts (s Sector) (d Bytes)) (→ (List Placed))
      (let* ((n (u32 d 0)) (ground (● s ground))
             (m (list 0.01
                      0.0
                      0.0
                      0.0
                      0.0
                      0.01
                      0.0
                      0.0
                      0.0
                      0.0
                      0.01
                      0.0
                      (i64->f64 (● ground west))
                      -12.0
                      (i64->f64 (● ground north))
                      1.0))
             (base (+ 4 (* 20 n))))
        (map (lambda (i) (placed d i base m)) (iota n))))
    ;; The mesh ends in eight-byte fixture records, their count and LIT1.
    ;; Centimetre positions use the same origin as the city vertices.
    (define (fixture (s Sector) (d Bytes) (i I64)) (→ Punctual)
      (let ((coordinate (lambda ((at I64) (base I64)) (→ F32)
                          (f64->f32 (+ (i64->f64 base) (* 0.01 (i64->f64 (u16 d at))))))))
        (point-light (new Vec3f (x (coordinate i (● s ground west)))
                          (y (coordinate (+ i 2) -12)) (z (coordinate (+ i 4) (● s ground north))))
                     (new Vec3f (x 26.0) (y (* 26.0 0.72)) (z (* 26.0 0.43))) 26.0)))
    (define (sector-lights (s Sector) (d Bytes)) (→ (List Punctual))
      (let ((end (array-length d)))
        (if (or (< end 8) (not (= (u32 d (- end 4)) 827607372))) (Nil)
            (let* ((count (u32 d (- end 8))) (start (- (- end 8) (* count 8))))
              (when (< start 4) (panic "invalid city light table"))
              ;; Older sectors also name shop fixtures (kind 1). Their
              ;; emissive sign geometry now supplies that light.
              (let ((offsets (map (lambda (i) (+ start (* 8 i))) (iota count))))
                (map (lambda (at) (fixture s d at))
                     (filter (lambda (at) (= (u8->i32 (array-ref d (+ at 6))) 0)) offsets)))))))
    (define (load-streets! (streets Streets) (r api:Renderer) (files (List Bytes))
                           (progress (Fn I64 I64 → Unit))) (→ Atlas)
                           (read-atlas-with-meshes files
                                                   (lambda (sector bytes total)
                                                     (let ((parts (sector-parts sector bytes))
                                                           (id (● sector id)))
                                                       (unless (null? parts)
                                                         (set! (● streets handles)
                                                               (table-set (● streets handles)
                                                                          (show id)
                                                                          (api:create-static-geometry!
                                                                           r
                                                                           parts
                                                                           bytes))))
                                                       (set! (● streets lights)
                                                             (append (sector-lights sector bytes)
                                                                     (● streets lights)))
                                                       (progress (+ id 1) total)))))
    (define (nearby-geometry (streets Streets) (g Area)) (→ (List api:GeometryHandle))
      (fold-right (lambda (s tail) (match (table-ref (● streets handles) (show (● s id)))
                                     ((Some h) (Cons h tail)) (_ tail)))
                  (Nil) (● g sectors)))
    (define (city-materials) (→ Gltf)
      (new Gltf
        (buffers (Nil))
        (size 0)
        (images (map FileSource
                     (list "sf-facade.png"
                           "sf-stucco.png"
                           "sf-brick.png"
                           "sf-works.png"
                           "sf-office.png")))
        (materials paints)
        (placed (Nil))))))
