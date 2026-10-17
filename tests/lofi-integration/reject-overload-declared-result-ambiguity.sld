(import
 (lofi base))
(define-overload result (-> I64) (lambda () (ann 42 I64)))
(define-overload result (-> Bool) (lambda () #t))
(result)
