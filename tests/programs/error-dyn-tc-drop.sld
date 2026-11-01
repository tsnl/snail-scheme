(import
 (snail core base))
(effect audit ((note (-> Unit))))
(struct Resource
  ((value Any)))
(instance (Drop (! dyn-tc) Resource)
  (define (drop resource) (ann (Resource-value resource) I64) (unit)))
