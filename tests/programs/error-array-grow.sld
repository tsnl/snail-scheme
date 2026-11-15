(import
 (snail core base))
(define (grow (items (Array I64))) (→ Unit) (! mut)
  (array-push! items 1))
