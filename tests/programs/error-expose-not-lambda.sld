(import
 (snail core base))

;; An exposed function is exported through a wrapper that calls its code
;; directly, so its definition must be a lambda, not a closure computed at
;; startup.
(define (adder (k I64)) (→ (dyn (Fn I64 → I64))) (lambda (x) (+ x k)))
(define add-one (→ (dyn (Fn I64 → I64))) (adder 1))
(expose add-one "add_one")
