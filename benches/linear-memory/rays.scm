;; The Last Mile visibility query sweeps the same walls for each ray.
(import
 (snail core base)
 (snail shell game physics))

(define walls (→ (List Footprint))
  (map (lambda (i)
         (footprint (+ 2.0 (i64->f64 i))
                    (- (i64->f64 (remainder (* i 7) 11)) 5.0) 0.5 1.25)) (iota 12)))

(define (cast-rays (count I64) (seed F64)) (→ F64)
  (let ((scene walls) (p (xz 0.0 seed)) (flat (xz 1.0 0.0)) (slope (xz 1.0 0.125)))
    (let loop ((n count) (z seed) (sum 0.0))
      (if (= n 0) sum
          (begin
            (set! (● p z) z)
            (let ((t (trace-distance p (if (= (remainder n 2) 0) flat slope) 40.0 scene)))
              (loop (- n 1) (if (> z 5.0) (- z 9.875) (+ z 0.28125)) (+ sum t))))))))

(expose cast-rays "cast-rays")
