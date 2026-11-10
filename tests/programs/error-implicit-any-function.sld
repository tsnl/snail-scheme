(import
 (snail core base))

(: accept (impl (Fn (dyn (Fn I64 -> I64)) -> I64)))
(define (accept function) (function 1))

(: dynamic (impl (Fn Any -> Any)))
(define (dynamic value) value)
(accept dynamic)
