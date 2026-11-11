(import
 (snail core base))

;; A FnOnce runs once, so nothing copies one.
(define copies (→ (Pair (dyn (FnOnce → Unit)) (dyn (FnOnce → Unit))))
  (clone (once (lambda () (unit)))))
