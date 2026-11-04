(import
 (snail core base))

(typeclass (Grow A)
  (type Output)
  (: grow (-> A Output)))
(instance (Grow A)
  (requires (Grow (List A)))
  (type Output (Grow.Output (List A)))
  (define (grow value) (grow (list value))))
(grow (ann 1 I64))
