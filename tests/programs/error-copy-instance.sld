(import
 (snail core base))
(typeclass (Twice T)
  (: twice (-> T (Pair T T))))
(instance (Twice (Option A))
  (define (twice value) (Pair value value)))
(twice (Some 1))
