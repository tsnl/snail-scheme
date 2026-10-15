(import (snail strict))

(define (exercise amount)
  (define (add value) (+ amount value))
  (define alias add)
  (define (invoke value) (alias value))
  (invoke 2))

(exercise 40)
