(import
 (snail core base))
(struct Resource
  ((value I64)))
(define (erase (resource (Rc Resource))) (→ Any)
  (Any resource))
