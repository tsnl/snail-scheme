(import
 (snail core base))

;; A Drop instance is declared beside its type.
(instance (Drop (!) (Pair A B))
  (define (drop pair)
    (unit)))
