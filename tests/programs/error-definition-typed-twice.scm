(import
 (snail core base))
(define increment (→ (Fn I64 → I64)) (lambda ((n I64)) (→ I64) (+ n 1)))
