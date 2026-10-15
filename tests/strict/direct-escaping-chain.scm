(import (snail strict))

(define (make-probe)
  (define (first) (second))
  (define (second) (lambda () (vector-ref later 0)))
  (define saved (first))
  (define later (make-vector 1 42))
  saved)

((make-probe))
