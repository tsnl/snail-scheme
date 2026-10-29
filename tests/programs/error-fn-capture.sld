(import
 (snail core base)
 (snail core io))

;; A `fn` cannot read a local of the code around it.
(: greet (-> String Unit ! console))
(define (greet name)
  (let ((say (fn () (write-line name))))
    (say)))
