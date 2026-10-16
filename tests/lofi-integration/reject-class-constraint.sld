(import (lofi base))
(def Combine (typeclass ( T) (: combine (-> T T T))))
(def lofi-migration-instance-1 (instance (Combine I64) (combine (lambda (a b) (+ a b)))))

(def twice (All (T) (-> T T))
     (lambda (x) (combine x x)))
(ann 42 I64)
