(import (snail strict))
(: worker (-> (Rest I32) I32))
(define (worker . xs) (car xs))
42
