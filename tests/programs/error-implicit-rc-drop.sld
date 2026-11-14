(import
 (snail core base))
(record Resource
  ((value I64)))
(define (forget (resource (Rc Resource))) (→ Unit) (unit))
