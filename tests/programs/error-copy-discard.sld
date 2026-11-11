(import
 (snail core base))
(: first (All (A B) (impl (Fn (Pair A B) -> A))))
(define (first pair)
  (match pair
    ((Pair a _) a)))
(first (Pair 1 2))
