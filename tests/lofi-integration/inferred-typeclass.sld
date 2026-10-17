(import
 (lofi base))
(def Combine (typeclass ( T) (: combine (-> T T T))))
(def lofi-migration-instance-1 (instance (Combine I64) (combine (lambda (a b) (+ a b)))))
(def lofi-migration-instance-2 (instance (Combine F64) (combine (lambda (a b) (f64-add a b)))))
(def twice
     (lambda (x) (combine x x)))
(if (f64-eq (twice 1.5) 3.0) (twice (ann 21 I64)) (ann 0 I64))
