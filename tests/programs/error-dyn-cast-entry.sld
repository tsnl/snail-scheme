(import
 (snail core base))

(define value (→ Any) "bad")

(define main
  (lambda ()
    (ann value I64)
    (unit)))
