(import
 (snail core base))
(: same (All (A) (requires (Copy B)) (-> A A)))
(define (same value) value)
(same 1)
