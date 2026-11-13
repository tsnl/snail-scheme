(import
 (snail core base))

;; Cloning a value of a type variable needs the row of its copy.
(define (twin (value A)) (→ (Pair A A)) (∀ (A))
  (clone value))
