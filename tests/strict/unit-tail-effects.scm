(import (snail strict))

(define digits (ref 0))
(define (visit n)
  (when (> n 0)
    (visit (- n 1))
    (ref-set! digits (+ (* 10 (ref-get digits)) n))
    (unit)))

(visit 9)
(ref-get digits)
