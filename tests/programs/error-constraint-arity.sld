(import
 (snail core base))
;; A signature may come before the class its constraint names.
(define (f (x T)) (→ T) (∀ (T)) (⊨ (Pairing T)) x)
(typeclass (Pairing A B)
  (declare (pair (a A) (b B)) (→ Unit)))
