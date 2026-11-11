(import
 (snail core base))

(define (accept (function (dyn (Fn I64 → I64)))) (→ I64) (function 1))

(define (dynamic (value Any)) (→ Any) value)
(accept dynamic)
