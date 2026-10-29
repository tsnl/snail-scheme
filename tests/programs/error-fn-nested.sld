(import
 (snail core base)
 (snail core io))

;; A lambda inside a `fn` cannot carry a capture out for it.
(: greet (-> String Unit ! console))
(define (greet name)
  (let ((say (fn () ((lambda () (write-line name))))))
    (say)))
