(import
 (snail core base))
(define (duplicate (value T)) (→ (Pair T T)) (∀ T) (Pair value value))
(duplicate 1)
