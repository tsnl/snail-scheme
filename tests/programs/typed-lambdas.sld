(import
 (snail core base)
 (snail core io))

;; ANCHOR: lambdas
;; A lambda takes a function definition's header, and a definition of a
;; typed lambda is that function definition.
(define double (lambda ((n I64)) (→ I64) (* n 2)))

(define identity (lambda ((value T)) (→ T) (∀ (T)) value))

(define report
  (lambda ((label String) (n I64)) (→ Unit) (! output-port)
    (write-line (string-append label " " (show n)))))

(define (apply-twice (f (Fn I64 → I64)) (n I64)) (→ I64)
  (f (f n)))
;; ANCHOR_END: lambdas

(define (main) (→ Unit) (! output-port)
  (report "double" (double 21))
  (write-line (identity "generic"))
  (report "identity" (identity 5))
  (report "inline" (apply-twice (lambda ((n I64)) (→ I64) (+ n 1)) 5))
  (let ((scale (lambda ((n I64) (by I64)) (→ I64) (* n by))))
    (report "local" (scale 6 7)))
  (define add (lambda ((a I64) (b I64)) (→ I64) (+ a b)))
  (report "local define" (add 1 2)))
