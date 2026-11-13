(import
 (snail core base)
 (snail core io))

(typeclass (Bad A)
  (type Output)
  (declare (bad (value A)) (→ A) (! Output)))
