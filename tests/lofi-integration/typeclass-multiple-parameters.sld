(import (lofi base))
(def Convert (typeclass ( A B) (: convert (-> A B))))
(def lofi-migration-instance-1 (instance (Convert I64 I32) (convert i64->i32)))
(def lofi-migration-instance-2 (instance (Convert I64 F64) (convert i64->f64)))

(def narrow I32
     (convert (ann 42 I64)))

(def floating F64
     (convert (ann 42 I64)))
(if (if (= narrow (ann 42 I32)) (= floating 42.0) #f) (ann 42 I64) (unreachable))
