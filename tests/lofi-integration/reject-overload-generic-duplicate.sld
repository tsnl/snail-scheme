(import
 (lofi base))
(define-overload choose (All (T) (-> T T)) (lambda (value) value))
(define-overload choose (All (U) (-> U U)) (lambda (value) value))
42
