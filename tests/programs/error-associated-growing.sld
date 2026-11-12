(import
 (snail core base))

(typeclass (Grow A)
  (type Output)
  (: grow (Fn A → Output)))
(instance (Grow A)
  (⊨ (Grow (List A)))
  (type Output (Grow.Output (List A)))
  (define grow (lambda (value) (grow (list value)))))
(grow (ann 1 I64))
