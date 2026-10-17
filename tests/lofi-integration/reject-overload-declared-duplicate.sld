(import
 (lofi base))
(define-overload add (-> I64 I64 I64) i64-add)
(define-overload add (-> I64 I64 I64) (lambda (left right) (i64-add left right)))
42
