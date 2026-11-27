;; Split-sum environment lighting. The same filter runs in the build producer
;; for shipped skies and once on an HDR imported into the viewer.
(define-library (snail shell graphics forward bake)
  (export bake-environment
          bake-brdf
          sky-radiance
          white-radiance
          key-direction
          key-color
          cube-size
          mip-count)
  (import
   (snail core base)
   (snail shell math)
   (only (snail shell game rigid-body) V3 v3 v+ v- scaled dot cross squared unit-vector)
   (snail shell graphics pod))
  (begin
    (define cube-size (→ I64) 32)
    (define mip-count (→ I64) 6)
    (define (white-radiance (d V3)) (→ V3) (v3 1.0 1.0 1.0))
    (define (key-direction (id I64)) (→ V3)
      (unit-vector (case id ((0) (v3 -0.67 0.41 -0.62)) ((1) (v3 0.18 0.93 -0.32))
                         ((2) (v3 -0.79 0.19 -0.58)) (else (v3 0.72 0.49 0.48)))))
    (define (key-color (id I64)) (→ V3)
      (case id ((0) (v3 3.8 2.8 1.96)) ((1) (v3 3.9 3.8 3.48))
            ((2) (v3 4.5 1.87 0.65)) (else (v3 0.25 0.34 0.58))))
    (define (mix3 (a V3) (b V3) (t F64)) (→ V3) (v+ (scaled a (- 1.0 t)) (scaled b t)))
    (define (sky-radiance (id I64) (d V3)) (→ V3)
      (let* ((zenith (case id ((0) (v3 0.14 0.34 0.70)) ((1) (v3 0.12 0.32 0.65))
                           ((2) (v3 0.17 0.24 0.43)) (else (v3 0.009 0.020 0.075))))
             (horizon (case id ((0) (v3 0.88 0.89 0.92)) ((1) (v3 0.87 0.97 1.12))
                            ((2) (v3 1.35 0.56 0.26)) (else (v3 0.057 0.089 0.16))))
             (height (● d y)) (sky (mix3 horizon zenith (sqrt (max 0.0 height))))
             (glow (expt (max 0.0 (dot d (key-direction id))) 12.0)))
        (if (< height 0.0) (mix3 (scaled horizon 0.12) horizon (expt (+ 1.0 height) 12.0))
            (v+ sky (scaled (key-color id) (* 0.11 glow))))))
    (define (cube-direction (face I64) (u F64) (v F64)) (→ V3)
      (unit-vector (case face ((0) (v3 1.0 (negate v) (negate u))) ((1) (v3 -1.0 (negate v) u))
                         ((2) (v3 u 1.0 v)) ((3) (v3 u -1.0 (negate v)))
                         ((4) (v3 u (negate v) 1.0)) (else (v3 (negate u) (negate v) -1.0)))))
    (define (radical (i I64)) (→ F64)
      (let loop ((v i) (step 0.5) (sum 0.0))
        (if (= v 0) sum (loop (quotient v 2) (* 0.5 step)
                              (+ sum (* step (i64->f64 (remainder v 2))))))))
    (define (half-vectors (r F64) (count I64)) (→ (List V3))
      (map (lambda (i)
             (let* ((x (radical i)) (phi (/ (* (* 2.0 pi) (i64->f64 i)) (i64->f64 count)))
                    (cosine (sqrt (/ (- 1.0 x) (+ 1.0 (* (- (* (* (* r r) r) r) 1.0) x)))))
                    (sine (sqrt (max 0.0 (- 1.0 (* cosine cosine))))))
               (v3 (* (cos phi) sine) (* (sin phi) sine) cosine))) (iota count)))
    (define (filtered (sample (Fn V3 → V3)) (n V3) (hs (List V3))) (→ V3)
      (let* ((axis (if (< (abs (● n y)) 0.99) (v3 0.0 1.0 0.0) (v3 1.0 0.0 0.0)))
             (t (unit-vector (cross axis n))) (b (cross n t)))
        (let loop ((rest hs) (sum (v3 0.0 0.0 0.0)) (weight 0.0))
          (match rest ((Nil) (scaled sum (/ 1.0 (max 1e-8 weight)))) ((Cons h next)
                                                                      (let* ((z (● h z))
                                                                             (w (- (* (* 2.0 z) z)
                                                                                   1.0))
                                                                             (l (v+ (scaled n w)
                                                                                    (scaled
                                                                                     (v+ (scaled t
                                                                                                 (●
                                                                                                  h
                                                                                                  x))
                                                                                         (scaled b
                                                                                                 (●
                                                                                                  h
                                                                                                  y)))
                                                                                     (* 2.0 z)))))
                                                                        (if (<= w 0.0)
                                                                            (loop next sum weight)
                                                                            (loop next
                                                                                  (v+ sum
                                                                                      (scaled
                                                                                       (sample l)
                                                                                       w))
                                                                                  (+ weight
                                                                                     w)))))))))
    (define (write-half! (out Bytes) (at I64) (x F64)) (→ Unit)
      (let ((bits (half-bits (f64->f32 (min 65504.0 x)))))
        (array-set! out at (i32->u8 (i64->i32 bits)))
        (array-set! out (+ at 1) (i32->u8 (i64->i32 (quotient bits 256))))))
    (define (write-rgb! (out Bytes) (at I64) (color V3)) (→ Unit)
      (write-half! out at (● color x)) (write-half! out (+ at 2) (● color y))
      (write-half! out (+ at 4) (● color z)) (write-half! out (+ at 6) 1.0))
    (define (cube-level (sample (Fn V3 → V3)) (level I64) (side I64)) (→ Bytes)
      (let* ((out (make-array (* (* 48 side) side) (i32->u8 0)))
             (hs (half-vectors (/ (i64->f64 level) (i64->f64 (- mip-count 1))) 64))
             (coord
              (lambda ((x I64)) (→ F64) (- (/ (+ (* 2.0 (i64->f64 x)) 1.0) (i64->f64 side)) 1.0))))
        (for-each (lambda (i) (let ((d (cube-direction (quotient i (* side side))
                                                       (coord (remainder i side))
                                                       (coord (remainder (quotient i side) side)))))
                                (write-rgb! out
                                            (* 8 i)
                                            (if (= level 0) (sample d) (filtered sample d hs)))))
                  (iota (* (* 6 side) side))) out))
    (define (basis (d V3)) (→ (List F64))
      (let ((x (● d x)) (y (● d y)) (z (● d z)))
        (list 0.2820947918 (* 0.4886025119 y) (* 0.4886025119 z) (* 0.4886025119 x)
              (* (* 1.092548431 x) y)
              (* (* 1.092548431 y) z)
              (* 0.3153915653 (- (* (* 3.0 z) z) 1.0))
              (* (* 1.092548431 x) z) (* 0.5462742153 (- (* x x) (* y y))))))
    (define (irradiance (sample (Fn V3 → V3))) (→ Bytes)
      (let ((coeff (make-array 9 (v3 0.0 0.0 0.0))) (count 1024))
        (for-each (lambda (i)
                    (let* ((y (- 1.0 (/ (+ (* 2.0 (i64->f64 i)) 1.0) (i64->f64 count))))
                           (r (sqrt (- 1.0 (* y y)))) (a (* 2.399963229728653 (i64->f64 i)))
                           (d (v3 (* r (cos a)) y (* r (sin a)))) (rgb (sample d)))
                      (for-each (lambda (kv) (let ((k (● kv first)) (v (● kv second)))
                                               (array-set! coeff
                                                           k
                                                           (v+ (array-ref coeff k)
                                                               (scaled rgb v)))))
                                (zip (iota 9) (basis d)))))
                  (iota count))
        (pack (ann (shape) (Shape Vec4f))
              (map (lambda (k) (let ((c (scaled (array-ref coeff k)
                                                (* (/ (* 4.0 pi) (i64->f64 count))
                                                   (cond ((= k 0) 1.0)
                                                         ((< k 4) (/ 2.0 3.0))
                                                         (else 0.25))))))
                                 (new Vec4f
                                   (x (f64->f32 (● c x)))
                                   (y (f64->f32 (● c y)))
                                   (z (f64->f32 (● c z)))
                                   (w 0.0))))
                   (iota 9)))))
    (define (bake-environment (sample (Fn V3 → V3))) (→ Bytes)
      (let loop ((level 0) (side cube-size) (out (irradiance sample)))
        (if (= level mip-count) out
            (loop (+ level 1)
                  (quotient side 2)
                  (array-append out (cube-level sample level side))))))
    (define (masking (cosine F64) (alpha F64)) (→ F64)
      (/ (* 2.0 cosine)
         (max 1e-8
              (+ cosine (sqrt (+ (* alpha alpha) (* (* (- 1.0 (* alpha alpha)) cosine) cosine)))))))
    (define (integrated (nv F64) (r F64) (hs (List V3))) (→ V3)
      (let ((v (v3 (sqrt (- 1.0 (* nv nv))) 0.0 nv)) (alpha (* r r)))
        (scaled (fold-left (lambda (sum h)
                             (let* ((vh (max 0.0 (dot v h)))
                                    (nh (● h z))
                                    (nl (- (* (* 2.0 vh) nh) nv)))
                               (if (<= nl 0.0) sum
                                   (let ((w (/ (* (* (masking nv alpha) (masking nl alpha)) vh)
                                               (max 1e-8 (* nv nh))))
                                         (f (expt (- 1.0 vh) 5.0)))
                                     (v+ sum (v3 (* w (- 1.0 f)) (* w f) 0.0))))))
                           (v3 0.0 0.0 0.0)
                           hs)
                (/ 1.0 (i64->f64 (length hs))))))
    (define (bake-brdf) (→ Bytes)
      (let ((bytes (make-array (* (* 32 32) 8) (i32->u8 0))))
        (for-each (lambda (y) (let* ((r (/ (i64->f64 y) 31.0)) (hs (half-vectors r 128)))
                                (for-each (lambda (x) (write-rgb! bytes (* 8 (+ (* y 32) x))
                                                                  (integrated
                                                                   (max 0.001 (/ (i64->f64 x) 31.0))
                                                                   r
                                                                   hs)))
                                          (iota 32))))
                  (iota 32))
        bytes))))
