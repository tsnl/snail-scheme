(import
 (snail core base)
 (snail core io))

;; An Any records no effects, so a downcast to a function that
;; performs one could return a function that hides it.
(define (noisy) (→ Unit) (! output-port) (write-line "noisy"))

(define (back (box Any)) (→ (Option (Fn → Unit ! output-port)))
  (downcast (Fn → Unit ! output-port) box))

(define (main) (→ Unit)
  (back (Any 1))
  (unit))
