(import
 (snail core base))
(record Resource
  ((value I64)))
(define (reader (resource (Rc Resource))) (→ (Fn → I64))
  (lambda () (● resource value)))
