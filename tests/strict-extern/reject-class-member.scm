(import (snail strict))
(define-class (Combine T) (: combine (-> T T T)))
(define-instance (Combine Bool) (combine native-add))
(define-extern native-add "probe" "add" (-> I32 I32 I32))
42
