(import (snail strict))

(define state (ref 0))
(: checked (-> I64))
(define (checked)
  (define (read-later)
    (ref-set! state 7)
    (vector-ref later 0))
  (define early (read-later))
  (define later (make-vector 1 42))
  early)
(: observed (-> I64))
(define (observed) (ref-get state))

42
