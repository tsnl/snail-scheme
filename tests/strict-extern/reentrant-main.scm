(import (snail strict))
(define-extern callback "probe" "callback" (-> Unit))
(: worker (-> I32 I32))
(define (worker value) value)
(callback)
42
