(import
 (snail core base))
(effect audit ((note (-> Unit))))
(struct Resource
  ((name String)))
(instance (Drop (! audit) Resource) (define (drop resource) (note)))
(: integer (-> Any I64 ! dyn-tc))
(define (integer value) value)
(: bad (-> Unit ! dyn-tc))
(define (bad) (let ((resource (Resource "r"))) (integer "bad") (panic "unreachable")))
