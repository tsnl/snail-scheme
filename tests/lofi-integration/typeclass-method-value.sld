(import (lofi base))
(def Combine (typeclass ( T) (: combine (-> T T T))))
(def lofi-migration-instance-1 (instance (Combine I64) (combine (lambda (a b) (+ a b)))))
(def combine-alias
     combine)

(def selected (-> I64 I64 I64)
     combine-alias)
(def twice-with
     (lambda (operation x) (operation x x)))
(twice-with selected (ann 21 I64))
