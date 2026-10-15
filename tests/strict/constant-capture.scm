(import (snail strict))

;; Constants and mutable aliases share a recursive scope. Escaping closures
;; must preserve separate activations while all aliases observe one Ref.
(define (make-step start)
  (define (advance delta)
    (ref-set! alias (+ (ref-get state) delta))
    (+ factor (remainder (ref-get alias) modulus)))
  (define factor 7)
  (define modulus 16)
  (define state (ref start))
  (define alias state)
  (lambda (delta) (advance delta)))
(define first (make-step 1))
(define second (make-step 10))
(+ (first 2) (+ (second 3) (first 4)))
