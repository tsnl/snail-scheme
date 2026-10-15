(import (snail strict))

;; Both concrete factories own their nested creation at this first event.
;; A later demand must not lend its initialized globals to the earlier code.
(define (make ignored) (lambda () later))
(define early ((make #t)))
(define later 42)
(define late (make 1))
early
