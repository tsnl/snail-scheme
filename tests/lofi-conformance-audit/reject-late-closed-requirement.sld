(import
 (lofi primitive))
(def Equal (typeclass (T) (: same? (-> T T Bool))))
((lambda (value)
   (begin
     (def inner (All () (requires (Equal I64)) (-> Bool))
          (lambda () (begin value #t)))
     (ann 42 I64)))
 (ann 42 I64))
