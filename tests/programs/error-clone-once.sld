(import
 (snail core base))

;; A FnOnce runs once, so nothing copies one.
(: copies (Pair (FnOnce Unit) (FnOnce Unit)))
(define copies
  (clone (once (lambda () (unit)))))
