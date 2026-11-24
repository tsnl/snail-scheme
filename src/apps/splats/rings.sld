;; Three rings of gaussians, the cloud a viewer opens on: one ring three
;; times, each copy on its own row of the transforms table. Posing the
;; rows each frame turns two rings linked like a chain's and tumbles a
;; third, smaller, around them, while the gaussians stay as they were
;; written.
(define-library (apps splats rings)
  (export
   rings
   ring-poses
   pose)
  (import
   (snail core base)
   (snail shell math)
   (snail shell graphics pod)
   (snail shell graphics splat))
  (begin

    (define (vec3 (x F64) (y F64) (z F64)) (→ Vec3f)
      (new Vec3f (x (f64->f32 x)) (y (f64->f32 y)) (z (f64->f32 z))))

    ;; ---- The ring ----

    ;; How many gaussians a ring has.
    (define ring-size (→ I64) 20000)

    ;; A number in [0, 1) for each index and stream, by multiplicative
    ;; hashing.
    (define (hashed (index I64) (stream I64)) (→ F64)
      (/ (i64->f64 (modulo (* (+ (* index 7) (+ stream 1)) 2654435761) 4294967296)) 4294967296.0))

    ;; A torus of radii 1 and 0.3 in the xz plane, its gaussians stretched
    ;; along the ring, colored by their angle around it, with a sheen
    ;; toward +z in their first-degree coefficients. A turn by θ about y
    ;; takes x to (cos θ, 0, -sin θ), so the tangent at angle u, (-sin u,
    ;; 0, cos u), is θ = -(u + π/2), a quaternion of half that angle.

    (define (ring-gaussian (index I64) (transform I32)) (→ Gaussian)
      (let* ((u (* 2.0 (* pi (hashed index 0))))
             (v (* 2.0 (* pi (hashed index 1))))
             (r (+ 1.0 (* 0.3 (cos v))))
             (turn (/ (+ u (/ pi 2.0)) -2.0)))
        (new Gaussian
          (position (vec3 (* r (cos u)) (* 0.3 (sin v)) (* r (sin u))))
          (transform transform)
          (rotation (new Vec4h (x 0.0) (y (f64->f32 (sin turn))) (z 0.0) (w (f64->f32 (cos turn)))))
          (scale-opacity (new Vec4h (x 0.07) (y 0.025) (z 0.025) (w 0.7))))))

    (define (ring-colors (index I64)) (→ (List Vec3f))
      (let ((u (* 2.0 (* pi (hashed index 0)))) (c (lambda (x) (/ (- x 0.5) 0.2820948))))
        (list (vec3 (c (+ 0.5 (* 0.45 (cos u))))
                    (c (+ 0.5 (* 0.45 (cos (+ u 2.1)))))
                    (c (+ 0.5 (* 0.45 (cos (+ u 4.2))))))
              (vec3 0.0 0.0 0.0)
              (vec3 0.4 0.4 0.4)
              (vec3 0.0 0.0 0.0))))

    ;; The three rings, ring k on row k.
    (define (rings) (→ Cloud)
      (let ((placed (concatenate (map (lambda (row)
                                        (map (lambda (index) (new Pair (first index) (second row)))
                                             (iota ring-size)))
                                      (iota 3)))))
        (pack-cloud (map (lambda (at) (ring-gaussian (● at first) (i64->i32 (● at second)))) placed)
                    (map (lambda (at) (ring-colors (● at first))) placed))))

    ;; ---- Poses ----

    ;; A transform from a 3x3 linear part, column by column, and a
    ;; translation.

    (define (pose (m (List F64)) (x F64) (y F64) (z F64)) (→ Mat4x4f)
      (let ((column (lambda (c w)
                      (new Vec4f
                        (x (f64->f32 (list-ref m (* 3 c))))
                        (y (f64->f32 (list-ref m (+ (* 3 c) 1))))
                        (z (f64->f32 (list-ref m (+ (* 3 c) 2))))
                        (w w)))))
        (new Mat4x4f
          (x (column 0 0.0))
          (y (column 1 0.0))
          (z (column 2 0.0))
          (w (new Vec4f (x (f64->f32 x)) (y (f64->f32 y)) (z (f64->f32 z)) (w 1.0))))))

    (define (about-y (a F64)) (→ (List F64))
      (list (cos a) 0.0 (negate (sin a)) 0.0 1.0 0.0 (sin a) 0.0 (cos a)))

    (define (about-x (a F64)) (→ (List F64))
      (list 1.0 0.0 0.0 0.0 (cos a) (sin a) 0.0 (negate (sin a)) (cos a)))

    (define (times (a (List F64)) (b (List F64))) (→ (List F64))
      (map (lambda (index)
             (let ((column (quotient index 3)) (row (remainder index 3)))
               (fold-left (lambda (sum k)
                            (+ sum
                               (* (list-ref a (+ (* k 3) row)) (list-ref b (+ (* column 3) k)))))
                          0.0
                          (iota 3))))
           (iota 9)))

    (define (scaled (m (List F64)) (s F64)) (→ (List F64))
      (map (lambda (x) (* s x)) m))

    ;; The rings at `t` seconds: the first flat at the origin, the second
    ;; standing through it, both turning together, and a third at 0.4 its
    ;; size tumbling on an orbit around them.

    (define (ring-poses (t F64)) (→ (List Mat4x4f))
      (let ((spin (about-y (* 0.3 t))))
        (list (pose spin 0.0 0.0 0.0)
              (pose (times spin (about-x (/ pi 2.0)))
                    (* 1.0 (cos (* 0.3 t)))
                    0.0
                    (negate (sin (* 0.3 t))))
              (pose (scaled (times (about-y t) (about-x (* 1.7 t))) 0.4)
                    (* 2.4 (cos (* 0.5 t)))
                    (* 0.6 (sin t))
                    (* 2.4 (sin (* 0.5 t)))))))

    ))
