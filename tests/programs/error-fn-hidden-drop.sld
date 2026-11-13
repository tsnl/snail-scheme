(import
 (snail core base))
(struct Resource
  ((value I64)))
(define (reader (resource (Rc Resource))) (→ (Fn → I64))
  (lambda () (● resource value)))
