(import
 (lofi base))
(define-overload identity (All (T) (-> T T)) (lambda (value) value))

(def impossible (All (T) (-> T Bool))
     (lambda (value) (identity value)))
(ann 42 I64)
