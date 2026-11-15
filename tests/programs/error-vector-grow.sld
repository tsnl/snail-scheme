(import
 (snail core base))
(define (grow (items (Vector I64))) (→ Unit) (! Mut)
  (vector-push! items 1))
