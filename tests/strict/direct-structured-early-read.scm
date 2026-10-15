(import (snail strict))

(define digits (ref 0))
(define (record digit)
  (ref-set! digits (+ (* 10 (ref-get digits)) digit))
  digit)
(: checked (-> I64))
(define (checked)
  (define early
    ((begin
       (record 3)
       (let ((ignored (record 4))) later))
     (record 1) (record 2)))
  (define (later left right) (+ left right))
  early)
(: observed (-> I64))
(define (observed) (ref-get digits))

42
