(import
 (snail core base)
 (snail core io))

;; Effects are erased before the signature is written, so the program
;; that loads a dynamic export could not check them.
(define (greet (name String)) (→ Unit) (! console)
  (write-line name))

(expose greet "greet" dynamic)
