(import
 (snail core base))

;; An exposed function is exported through a wrapper that calls its code
;; directly, so its definition must be a lambda, not a closure computed at
;; startup.
(: adder (-> I64 (-> I64 I64)))
(define (adder k) (lambda (x) (+ x k)))
(: add-one (-> I64 I64))
(define add-one (adder 1))
(expose add-one "add_one")
