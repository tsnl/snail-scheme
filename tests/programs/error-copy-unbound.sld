(import
 (snail core base))

(define (same (value A)) (→ A) (∀ A) (⊨ (Copy B)) value)

(define main
  (lambda ()
    (same 1)
    (unit)))
