(import
 (snail core base))

;; Dropping a value of a type variable needs the row of its release.
(define (discard-it (value A)) (→ Unit) (∀ (A))
  (drop value))
