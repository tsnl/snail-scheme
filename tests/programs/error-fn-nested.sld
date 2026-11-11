(import
 (snail core base)
 (snail core io))

;; A lambda inside a `fn` cannot carry a capture out for it.
(define (greet (name String)) (→ Unit) (! console)
  (let ((say (fn () ((lambda () (write-line name))))))
    (say)))
