(import
 (snail core base))
(define (grow (items (Array I64))) (→ Unit)
  (array-push! items 1))
