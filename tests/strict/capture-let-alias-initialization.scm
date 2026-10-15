(import (snail strict))

(define effects (ref 0))
(: checked (-> I64))
(define (checked)
  (define (make-probe)
    (let ((copy later))
      (ref-set! effects 1)
      (lambda () (copy 42))))
  (define saved (make-probe))
  (define (later x) x)
  (saved))
(: observed (-> I64))
(define (observed) (ref-get effects))

42
