(import (snail strict))
(define-class (Identity T) (: identity (-> T T)))
(define-overload invalid identity)
42
