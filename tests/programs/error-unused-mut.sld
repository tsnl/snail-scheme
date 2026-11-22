(import
 (snail core base)
 (snail core io))

;; A signature may not ask for a Mut its body never uses.
(define (double (mut Mut) (x I64)) (→ I64)
  (* x 2))

(define (main (mut Mut) (out OutputPort)) (→ Unit)
  (write-line out (i64->string (double mut 2)))
  (unit))
