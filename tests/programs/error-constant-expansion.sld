(import
 (snail core base))

(define too-large (→ (List I64)) (iota 20000))

(define (main) (→ Unit)
  (drop too-large))
