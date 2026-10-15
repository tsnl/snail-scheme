(import (snail strict))
(: worker (-> (Ref I32) I32))
(define (worker x) (ref-get x))
42
