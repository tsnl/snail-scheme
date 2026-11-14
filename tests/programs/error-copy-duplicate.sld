(import
 (snail core base))

(define (duplicate (value T)) (→ (Pair T T)) (∀ (T)) (new Pair (first value) (second value)))

(define main
  (lambda ()
    (duplicate 1)
    (unit)))
