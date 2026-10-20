(import
 (lofi base))
(define-syntax m (syntax-rules () ((_ value) (+ value 1))))
(def Wrapped (datatype ()
               (wrapped
                (value I32 wrapped-value))))
(define-overload + (-> Wrapped I32 I32)
  (lambda (left right) (+ (wrapped-value left) right)))
(m (wrapped 41))
