;; Rigid parts in a model's local axes. A model faces -z. The physics
;; heading turns north through east, the raster's yaw in the opposite sense.
(define-library (snail shell game drawing)
  (export xyz piece place-parts)
  (import
   (snail core base)
   (snail shell math)
   (snail shell app)
   (snail shell game physics))
  (begin
    (define (xyz (x F64) (y F64) (z F64)) (→ Vec3)
      (new Vec3 (x (f64->f32 x)) (y (f64->f32 y)) (z (f64->f32 z))))
    (define (piece (mesh Mesh) (color I32) (x F64) (y F64) (z F64)
                   (width F64) (height F64) (depth F64) (glow F32)) (→ Item)
                   (Item-glow-set (item mesh (xyz x y z) (xyz width height depth) 0.0 color) glow))

    (define (place-parts (parts (List Item)) (p XZ) (height F64) (heading F64)) (→ (List Item))
      (let ((c (cos heading)) (s (sin heading)))
        (map (lambda (part)
               (let* ((v (● part position)) (x (f32->f64 (● v x))) (z (f32->f64 (● v z)))
                      (at (xyz (+ (● p x) (- (* c x) (* s z))) (+ height (f32->f64 (● v y)))
                               (+ (● p z) (+ (* s x) (* c z))))))
                 (Item-from-set
                  (Item-position-set (Item-yaw-set part (- (● part yaw) (f64->f32 heading))) at)
                  at)))
             parts)))))
