(import (lofi base))
(def Marker (typeclass ( T) (: mark (-> I64))))
(def lofi-migration-instance-1 (instance (Marker I32) (mark (lambda () (ann 20 I64)))))
(def lofi-migration-instance-2 (instance (Marker F64) (mark (lambda () (ann 22 I64)))))
;; The two methods have identical arrow shapes; their class arguments still
;; select distinct implementations.
(def mark-integer
     (inst mark I32))
(def mark-float
     (inst mark F64))
(+ (mark-integer) (mark-float))
