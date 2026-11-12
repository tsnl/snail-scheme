(import
 (snail core base))

;; A FnOnce runs once, so nothing copies one.
(define copies (→ (Pair (FnOnce → Unit) (FnOnce → Unit)))
  (clone (once (lambda () (unit)))))
