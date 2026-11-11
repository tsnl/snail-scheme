(import
 (snail core base))
(typeclass (Twice T)
  (: twice (impl (Fn T → (Pair T T)))))
(instance (Twice (Option A))
  (define twice (lambda (value) (Pair value value))))
(twice (Some 1))
