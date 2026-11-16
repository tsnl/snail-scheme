(import
 (snail core base)
 (snail core io))

;; Each initializer reads the other's value before its own is ready.
(define a (→ I64) (+ b 1))

(define b (→ I64) (+ a 1))

(define (main) (→ Unit) (! output-port)
  (write-line (show a)))
