(import
 (snail core base))

(define (identity (value T))
  (→ T)
  (∀ T T)
  value)
