(import
 (snail core base))
(record Resource
  ((value I64)))
(define (erase (resource (Rc Resource))) (→ Any)
  (Any resource))
