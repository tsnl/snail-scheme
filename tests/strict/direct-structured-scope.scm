(import (snail strict))

(define cell (ref 0))
(define answer
  ((let ((cell (ref (+ (ref-get cell) 1))))
     (define (finish amount)
       (ref-set! cell (+ (ref-get cell) amount))
       (ref-get cell))
     finish)
   (begin (ref-set! cell 40) 1)))

(if (and (= answer 42) (= (ref-get cell) 40)) 42 0)
