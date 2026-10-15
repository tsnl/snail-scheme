(import (snail strict))

(define digits (ref 0))
(define (record digit)
  (ref-set! digits (+ (* 10 (ref-get digits)) digit))
  digit)
(define answer
  ((let ((left (record 3)) (right (record 4)))
     (define middle (record 5))
     (define (finish first second)
       (record 7)
       (+ (+ first second) (+ (+ left right) middle)))
     (record 6)
     finish)
   (record 1) (record 2)))

(if (and (= answer 15) (= (ref-get digits) 1234567)) 42 0)
