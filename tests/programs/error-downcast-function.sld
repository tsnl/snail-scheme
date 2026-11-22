(import
 (snail core base)
 (snail core io))

;; An Any records no effects, so a downcast to a function that
;; performs one could return a function that hides it.
(define (noisy (out OutputPort)) (→ Unit) (! mut) (write-line out "noisy"))

(define (back (box Any)) (→ (Option (Fn → Unit ! mut)))
  (downcast (Fn → Unit ! mut) box))

(define (main) (→ Unit)
  (back (Any 1))
  (unit))
