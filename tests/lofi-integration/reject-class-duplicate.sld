(import (lofi base))
(def Combine (typeclass ( T) (: combine (-> T T T))))
(def lofi-migration-instance-1 (instance (Combine I64) (combine (lambda (a b) (+ a b)))))
(def lofi-migration-instance-2 (instance (Combine I64) (combine (lambda (a b) (- a b)))))
42
