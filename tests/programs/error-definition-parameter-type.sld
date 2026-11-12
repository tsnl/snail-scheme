(import
 (snail core base))

(define (identity (value I64))
  (→ I64)
  value)

(define main
  (lambda ()
    (identity #t)
    (unit)))
