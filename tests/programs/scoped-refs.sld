(import
 (snail core base)
 (snail core io)
 (only (snail shell game rigid-body) V3 v3))

;; ANCHOR: integrate
(define (advance! (position (MutRef V3)) (velocity (Ref V3)) (dt F64)) (→ Unit)
  (set! (● position x) (+ (● position x) (* dt (● velocity x))))
  (set! (● position y) (+ (● position y) (* dt (● velocity y))))
  (set! (● position z) (+ (● position z) (* dt (● velocity z)))))

(define (step! (p (MutRef V3)) (v (Ref V3))) (→ Unit)
  (advance! (ref! p) (ref v) 0.5))
;; ANCHOR_END: integrate

(define (sum (a (Ref I64)) (b (Ref I64))) (→ I64)
  (+ (ref-get a) (ref-get b)))

(define (count! (n I64) (x (MutRef I64))) (→ Unit)
  (if (= n 0) (unit)
      (begin (ref-set! x (+ (ref-get x) 1))
             (count! (- n 1) (ref! x)))))

(define (main (out OutputPort)) (→ Unit)
  (let* ((origin (v3 1.0 2.0 3.0))
         (p (ref-local origin))
         (v (ref-local (new V3 (x 4.0) (y -2.0) (z 6.0)))))
    (step! (ref! p) (ref v))
    (write-line out (show (f64->i64 (● p x))))
    (write-line out (show (f64->i64 (● p y))))
    (write-line out (show (f64->i64 (● p z))))
    (let ((snapshot (ref-get p)))
      (set! (● snapshot x) 99.0)
      (write-line out (show (f64->i64 (● p x)))))
    (ref-set! p origin)
    (set! (● origin x) 50.0)
    (write-line out (show (f64->i64 (● p x)))))
  (let ((counter (ref-local 0)))
    (count! 100000 (ref! counter))
    (write-line out (show (sum (ref counter) (ref counter))))))
