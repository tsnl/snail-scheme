(import (lofi base))
(def Combine (typeclass ( T) (: combine (-> T T T))))
(def lofi-migration-instance-1 (instance (Combine Bool) (combine native-add)))
(define-extern native-add "probe" "add" (-> I32 I32 I32))
42
