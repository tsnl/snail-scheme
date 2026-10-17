(import
 (lofi base))
(def implementation (All (T) (-> T T)) (lambda (value) value))
(define-overload identity implementation)
(identity (ann 42 I64))
