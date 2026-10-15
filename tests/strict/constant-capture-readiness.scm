(import (snail strict))

(define effects (ref 0))
(: checked (-> I64))
(define (checked)
  (define read-later
    (lambda ()
      (ref-set! effects (+ (ref-get effects) 1))
      later))
  (define invoke read-later)
  (define early (invoke))
  (define later 42)
  early)
(: observed (-> I64))
(define (observed) (ref-get effects))
42
