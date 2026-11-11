(import
 (snail core base))
(define (first (pair (Pair A B))) (→ A) (∀ A B)
  (match pair
    ((Pair a _) a)))
(first (Pair 1 2))
