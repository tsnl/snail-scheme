(import
 (snail core base))

(define (duplicate (value T)) (→ (Pair T T)) (∀ (T)) (Pair value value))

(define main
  (lambda ()
    (duplicate 1)
    (unit)))
