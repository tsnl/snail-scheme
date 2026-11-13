(import
 (snail core base))
(struct Resource
  ((value I64)))
(define (forget (resource (Rc Resource))) (→ Unit) (unit))
