(import
 (snail core base))

(define (memoize (f F)) (→ F) (∀ (F)) (cache f))
(define (main) (→ Unit) (unit))
