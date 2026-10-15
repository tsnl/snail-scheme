(import (snail strict))

(define effects (ref 0))
(: checked (-> I64))
(define (checked)
  (let ((x 42))
    (define (read-alias)
      (ref-set! effects 1)
      alias)
    (define early (read-alias))
    (define alias x)
    (read-alias)))
(: observed (-> I64))
(define (observed) (ref-get effects))

42
