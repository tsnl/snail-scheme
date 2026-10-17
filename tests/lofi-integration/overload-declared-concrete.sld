(import
 (lofi base))
(define-overload increment (-> I64 I64) (lambda (value) (i64-add value (ann 1 I64))))
(define-overload increment (-> F64 F64) (lambda (value) (f64-add value 1.0)))
(define-overload convert (-> I64 F64) i64->f64)
(define-overload convert (-> F64 I64) f64->i64)
(i64-add (increment (ann 0 I64)) (convert (increment (convert (ann 40 I64)))))
