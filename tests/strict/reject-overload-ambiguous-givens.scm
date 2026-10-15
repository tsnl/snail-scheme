(import (snail strict))
(: ignore (All (A R S) (=> ((+ (-> A A R)) (+ (-> A A S))) (-> A Unit))))
(define (ignore value) (+ value value) (unit))
42
