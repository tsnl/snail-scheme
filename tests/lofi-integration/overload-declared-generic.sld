(import (lofi base))
(define-overload choose (All (A B) (-> A B A)) (lambda (left right) left))
(define-overload choose (All (T) (-> T T)) identity)
(def identity
     (lambda (value) value))

(def constrained (All (T) (=> ((choose (-> T T))) (-> T T)))
     (lambda (value) (choose value)))
(def unary
     (ann choose (-> Bool Bool)))
(if (if (unary #t) (constrained #t) #f) (choose (ann 42 I64) #f) (unreachable))
