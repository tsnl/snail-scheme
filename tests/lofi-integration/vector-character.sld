(import
 (lofi base))
(def values
     (make-vector (ann 1 I64) #\λ))
(vector-ref values (ann 0 I64))
