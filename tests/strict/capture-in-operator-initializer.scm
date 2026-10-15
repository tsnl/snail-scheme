(import (snail strict))
(define (exercise x)
  ((let ((y x)) (lambda () y))))
(exercise 42)
