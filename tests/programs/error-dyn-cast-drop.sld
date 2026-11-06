(import
 (snail core base))
(effect audit ((note (-> Unit))))
(struct Resource
  ((value Any)))
(instance (Drop (! dyn-cast) Resource)
  (define (drop resource) (ann (::value resource) I64) (unit)))
