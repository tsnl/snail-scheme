(import
 (lofi base))

(def identity (All (T) (-> T T))
     (lambda (x) x))
((inst identity I64) (ann 42 I64))
