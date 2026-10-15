(import (snail strict))

(define state (ref 0))
(: calls (-> I64))
(define (calls) (ref-get state))
(: after-forward (-> I64))
(define (after-forward) (ref-get state))
(: checked (-> Unit))
(define (checked)
  (ref-set! state 1)
  (ann (ann 42 Top) Unit)
  (unit))
(: forward (-> Unit))
(define (forward)
  (define early (begin (ref-set! state 2) later (unit)))
  (define later (unit))
  early
  (unit))

42
