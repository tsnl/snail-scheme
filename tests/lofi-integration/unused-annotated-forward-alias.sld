(import
 (lofi base))

(def alias (All (T) (-> T T))
     later)
(def later
     (lambda (x) x))
(ann 42 I64)
