(import
 (snail core base))

(define (accept (function (Fn I64 → I64))) (→ I64) (function 1))

(define (dynamic (value Any)) (→ Any) value)

(define main
  (lambda ()
    (accept dynamic)
    (unit)))
