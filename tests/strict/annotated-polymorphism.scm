(import (snail strict))
(: identity (All (T Unused) (-> T T)))
(define (identity x) x)
(i32-add (identity (ann 40 I32)) (ann 2 I32))
