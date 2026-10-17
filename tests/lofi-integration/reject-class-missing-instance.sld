(import (lofi base))
(def Combine (typeclass ( T) (: combine (-> T T T))))
(def lofi-migration-instance-1 (instance (Combine I64) (combine (lambda (a b) (+ a b)))))
(def twice
     (lambda (x) (combine x x)))
(twice #t)
