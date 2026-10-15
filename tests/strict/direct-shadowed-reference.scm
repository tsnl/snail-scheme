(import (snail strict))

(define (exercise seed)
  (define cell (ref seed))
  (define (left n)
    (define (step)
      (ref-set! cell (+ (ref-get cell) 1))
      (right n))
    (step))
  (define (right n) (+ n (ref-get cell)))
  (let ((cell (ref 0))) (+ (left 1) (ref-get cell))))

(exercise 40)
