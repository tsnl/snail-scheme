(import
 (lofi base))
(define-overload wrapper (All (T) (-> T T)) (lambda (value) (via value)))
(define-overload wrapper (-> I64 Bool) (lambda (value) #t))
(define-overload via
  (All (A R) (=> ((target (-> A R))) (-> A R)))
  (lambda (value) (target value)))
(define-overload target (All (T) (-> T T)) (lambda (value) value))
(if (ann (wrapper (ann 42 I64)) Bool) (ann (wrapper (ann 42 I64)) I64) (unreachable))
