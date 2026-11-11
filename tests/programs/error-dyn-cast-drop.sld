(import
 (snail core base))
(effect audit ((note (dyn (Fn → Unit)))))
(struct Resource
  ((value Any)))
(instance (Drop (! dyn-cast) Resource)
  (define drop (lambda (resource) (ann (● resource value) I64) (unit))))
