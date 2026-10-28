(import
 (snail-core base)
 (snail-core io))

;; Effects are erased before the signature is written, so the program
;; that loads a dynamic export could not check them.
(: greet (-> String Unit ! console))
(define (greet name)
  (write-line name))

(expose greet "greet" dynamic)
