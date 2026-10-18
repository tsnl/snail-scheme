(import
 (lofi primitive))
(def Equal (typeclass (T) (: same? (-> T T Bool))))
(def equal-i64 (instance (Equal I64) (same? i64-eq)))
(def outer (All (T) (requires (Equal T)) (-> T Bool))
     (lambda (outer-value)
       (begin
         (def inner (All (T) (requires (Equal T)) (-> T Bool))
              (lambda (inner-value)
                (if (same? outer-value outer-value)
                    (same? inner-value inner-value)
                    #f)))
         (inner (ann 42 I64)))))
(if (outer (ann 42 I64)) (ann 42 I64) (ann 0 I64))
