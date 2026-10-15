(import (snail strict))

(define (make-probe count)
  (define (loop n)
    (define owned n)
    (define (hold) (lambda () owned))
    (if (= n 0)
        (hold)
        (let ((previous (loop (- n 1))) (current (hold)))
          (lambda () (+ (previous) (current))))))
  (loop count))

(+ 6 ((make-probe 8)))
