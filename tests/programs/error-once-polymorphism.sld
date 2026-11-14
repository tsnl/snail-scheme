(import
 (snail core base))

(define (duplicate (value T))
  (→ (Pair T T))
  (∀ (T))
  (⊨ (Copy T))
  (new Pair (first value) (second value)))

(define main
  (lambda ()
    (duplicate (once (lambda () (unit))))
    (unit)))
