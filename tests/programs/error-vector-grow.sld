(import
 (snail core base))
(define (grow (items (Vector I64))) (→ Unit) (! mut)
  (vector-push! items 1))
