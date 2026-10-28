(import
 (snail core base)
 (snail core io))

;; A signature may not name an effect its body never performs.
(: double (-> I64 I64 ! mut))
(define (double x)
  (* x 2))

(write-line (i64->string (double 2)))
