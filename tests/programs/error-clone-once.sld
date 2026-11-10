(import
 (snail core base))

;; A FnOnce runs once, so nothing copies one.
(: copies (Pair (dyn (FnOnce -> Unit)) (dyn (FnOnce -> Unit))))
(define copies
  (clone (once (lambda () (unit)))))
