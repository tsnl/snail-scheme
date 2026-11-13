(import
 (snail core base))

(define (duplicate (value T)) (→ (Pair T T)) (∀ (T)) (⊨ (Copy T)) (Pair value value))

(define main
  (lambda ()
    (duplicate (once (lambda () (unit))))
    (unit)))
