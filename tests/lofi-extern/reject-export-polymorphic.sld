(import
 (lofi base))

(def worker (All (T) (-> T T))
     (lambda (x) x))
(ann 42 I64)
