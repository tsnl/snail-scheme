(import (snail strict))
(: add (All (A R S) (=> ((+ A A R) (+ A A S)) (-> A R))))
(define (add value) (+ value value))
0
