(import
 (snail core base))

(define (first (pair (Pair A B))) (→ A) (∀ (A B))
  (match pair
    ((Pair a _) a)))

(define main
  (lambda ()
    (first (new Pair (first 1) (second 2)))
    (unit)))
