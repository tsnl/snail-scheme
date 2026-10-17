(import
 (lofi base))
(define-overload identity (-> Bool Bool) (lambda (value) value))
(define-overload identity (lambda (value) (ann value I64)))
(identity #t)
