(import (snail strict))
(define-overload select (All (T) (-> T T)) identity)
(define (identity x) x)
(if (and (select #t) (= (select 42) 42)) 42 (unreachable))
