(import
 (snail core base))

;; A statement's value is discarded, so it cannot be linear.
(define (forget) (→ Unit)
  (once (lambda () (unit)))
  (unit))

(define main
  (lambda ()
    (forget)
    (unit)))
