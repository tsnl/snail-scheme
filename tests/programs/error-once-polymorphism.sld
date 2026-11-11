(import
 (snail core base))
(define (duplicate (value T)) (→ (Pair T T)) (∀ T) (⊨ (Copy T)) (Pair value value))
(duplicate (once (lambda () (unit))))
