(import
 (snail core base))

;; A statement's value is discarded, so it cannot be linear.
(: forget (impl (Fn -> Unit)))
(define (forget)
  (once (lambda () (unit)))
  (unit))

(forget)
