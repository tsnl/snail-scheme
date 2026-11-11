(import
 (snail core base))

;; An exposed function is exported through a wrapper that calls its code
;; directly, so its definition must be a lambda, not a closure computed at
;; startup.
(: adder (impl (Fn I64 -> (dyn (Fn I64 -> I64)))))
(define (adder k) (lambda (x) (+ x k)))
(: add-one (dyn (Fn I64 -> I64)))
(define add-one (adder 1))
(expose add-one "add_one")
