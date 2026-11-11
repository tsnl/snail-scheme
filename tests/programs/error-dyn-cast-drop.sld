(import
 (snail core base))
(effect audit ((note (dyn (Fn → Unit)))))
(struct Resource
  ((value Any)))
(instance (Drop (! dyn-cast) Resource)
  (define drop (lambda (resource) (ann (::value resource) I64) (unit))))
