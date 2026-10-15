(import (snail strict))

(define state (ref 0))
(define (make-probe early?)
  (define probe
    (lambda ()
      (ref-set! state (+ 1 (ref-get state)))
      (later)))
  (define early (if early? (probe) 0))
  (define (later) (vector-ref payload 0))
  (define payload (make-vector 1 42))
  probe)
(define saved (make-probe #f))
(: checked (-> I64))
(define (checked) ((make-probe #t)))
(: before (-> I64))
(define (before) (ref-get state))
(: after (-> I64))
(define (after) (saved))
(: observed (-> I64))
(define (observed) (ref-get state))

42
