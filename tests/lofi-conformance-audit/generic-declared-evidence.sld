(import
 (lofi primitive))
(def Equal (typeclass (T) (: same? (-> T T Bool))))
(def unused (All (T) (requires (Equal T)) (-> T Bool)) (lambda (x) (same? x x)))
(ann 42 I64)
