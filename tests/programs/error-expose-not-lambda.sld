(import
 (snail core base))
(define (adder (k I64)) (→ (Fn I64 → I64)) (lambda (x) (+ x k)))
(define add-one (adder 1))
(expose add-one "add_one")
