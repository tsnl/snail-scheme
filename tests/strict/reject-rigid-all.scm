(import (snail strict))
(: identity (All (T) (-> T T)))
(define (identity x) (+ x 1))
(identity 41)
