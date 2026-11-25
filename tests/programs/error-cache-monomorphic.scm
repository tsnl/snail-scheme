(import
 (snail core base))

(define (identity (value T)) (→ T) (∀ (T)) value)
(define (main) (→ Unit)
  (let ((memo (cache identity))) (memo 1) (memo "one") (unit)))
