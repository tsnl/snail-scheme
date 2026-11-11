(import
 (snail core base))
(define (count (items (List T))) (→ I64) (∀ T) (length items))
(count (list 1 2))
