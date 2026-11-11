(import
 (snail core base)
 (snail core io))

(define (even? (n I64)) (→ Bool)
  (if (= n 0) #t (odd? (- n 1))))

(define (odd? (n I64)) (→ Bool)
  (if (= n 0) #f (even? (- n 1))))

(define (apply-n (f (dyn (Fn I64 → I64))) (n I64) (x I64)) (→ I64)
  (if (= n 0) x (apply-n f (- n 1) (f x))))

(display (even? 10000001))
(newline)
(display (apply-n (lambda (x) (+ x 2)) 5000000 0))
(newline)
(display (length (iota 1000000)))
(newline)
