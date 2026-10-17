(import
 (lofi primitive))
(def Equal (typeclass (T) (: same? (-> T T Bool))))
(def equal-i64 (instance (Equal I64) (same? i64-eq)))
(def outer (All (T) (-> T Bool))
     (lambda (value)
       (begin
         (def inner (-> Bool) (lambda () (same? value value)))
         (inner))))
(if (outer (ann 42 I64)) (ann 42 I64) (ann 0 I64))
