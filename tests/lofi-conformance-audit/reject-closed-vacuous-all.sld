(import
 (lofi primitive))
(def Equal (typeclass (T) (: same? (-> T T Bool))))
(def unused (All (A) (requires (Equal I64)) (-> I64 I64)) (lambda (x) x))
(ann 42 I64)
