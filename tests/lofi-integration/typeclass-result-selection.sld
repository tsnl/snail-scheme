(import
 (lofi base))
(def Zero (typeclass ( T) (: zero (-> T))))
(def lofi-migration-instance-1 (instance (Zero I32) (zero (lambda () (ann 0 I32)))))
(def lofi-migration-instance-2 (instance (Zero F64) (zero (lambda () 0.0))))

(def first I32
     (zero))

(def second F64
     (zero))
(if (if (i32-eq first (ann 0 I32)) (f64-eq second 0.0) #f) (ann 42 I64) (ann 0 I64))
