(import
 (lofi base))
(define-overload choose (All (T) (-> T T)) (lambda (value) value))
(define-overload choose (-> I64 I64) (lambda (value) value))
(if (choose #t) (ann 42 I64) (unreachable))
