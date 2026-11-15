(import
 (snail core base)
 (snail core io))

;; A signature may not name an effect its body never performs.
(define (double (x I64)) (→ I64) (! Mut)
  (* x 2))

(define main
  (lambda ()
    (write-line (i64->string (double 2)))
    (unit)))
