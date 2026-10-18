(import
 (lofi primitive))
(def Equal (typeclass (T) (: same? (-> T T Bool))))
(def equal-i64 (instance (Equal I64) (same? i64-eq)))
((lambda (value)
   (begin
     (def inner (All () (requires (Equal I64)) (-> Bool))
          (lambda () (begin value #t)))
     (ann 42 I64)))
 (ann 42 I64))
