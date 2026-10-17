(import
 (lofi base))
(define-overload distinguish (-> I32 I64) (lambda (value) (ann 20 I64)))
(define-overload distinguish (-> Bool I64) (lambda (value) (ann 22 I64)))
(+ (distinguish (ann 0 I32)) (distinguish #f))
