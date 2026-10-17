(import (lofi base))
(define-overload source (-> I64) (lambda () (ann 42 I64)))
(define-overload source (-> Bool) (lambda () #t))
(define-overload destination (-> I64 F64) i64->f64)
(define-overload compose
  (All (A B) (=> ((source (-> B)) (destination (-> B A))) (-> A)))
  (lambda () (destination (source))))
(define-overload reverse-compose
  (All (A B) (=> ((destination (-> B A)) (source (-> B))) (-> A)))
  (lambda () (destination (source))))

(def first F64
     (compose))

(def second F64
     (reverse-compose))
(if (if (= first 42.0) (= second 42.0) #f) (ann 42 I64) (unreachable))
