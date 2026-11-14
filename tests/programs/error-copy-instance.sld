(import
 (snail core base))

(typeclass (Twice T)
  (declare (twice (value T)) (→ (Pair T T))))

(instance (Twice (Option A))
  (define (twice (value (Option A))) (→ (Pair (Option A) (Option A)))
    (new Pair (first value) (second value))))

(define main
  (lambda ()
    (twice (Some 1))
    (unit)))
