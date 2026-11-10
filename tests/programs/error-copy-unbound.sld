(import
 (snail core base))
(: same (All (A) (requires (Copy B)) (impl (Fn A -> A))))
(define (same value) value)
(same 1)
