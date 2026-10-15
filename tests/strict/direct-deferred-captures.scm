(import (snail strict))

(define (exercise)
  (define (choose use-later?) (if use-later? (later) 20))
  (define before (choose #f))
  (define (later) (vector-ref payload 0))
  (define payload (make-vector 1 22))
  (+ before (choose #t)))

(exercise)
