(import
 (snail core base)
 (snail core io))

;; A `fn` cannot read a local of the code around it.
(define (greet (name String)) (→ Unit) (! output-port)
  (let ((say (fn () → (write-line name))))
    (say)))
