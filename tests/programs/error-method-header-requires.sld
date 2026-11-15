(import
 (snail core base))
(typeclass (Select T) (declare (choose (tag T) (value A)) (→ A) (∀ (A))))
(instance (Select I64) (define (choose (tag I64) (value B)) (→ B) (∀ (B)) (⊨ (Show (!) B)) value))
