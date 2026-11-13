(import
 (snail core base))
(define (forget (value T)) (→ Unit) (∀ T) (⊨ (Copy T)) (unit))
