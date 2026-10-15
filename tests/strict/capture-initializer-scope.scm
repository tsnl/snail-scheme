(import (snail strict))

(define effects (ref 0))
(define x 40)
(define (make-probe)
  (let ((x (begin (ref-set! effects (+ (ref-get effects) 1)) 1))
        (outer (begin (ref-set! effects (+ (ref-get effects) 10))
                      (lambda () x))))
    (lambda () (+ x (outer)))))

(define saved (make-probe))
(+ (saved) (ref-get effects))
