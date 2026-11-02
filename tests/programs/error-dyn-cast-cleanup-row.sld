(import
 (snail core base))
(effect audit ((note (-> Unit))))
(struct Resource
  ((name String)))
(instance (Drop (! audit) Resource) (define (drop resource) (note)))
(: integer (-> Any I64 ! dyn-cast))
(define (integer value) value)
(: bad (-> Unit ! dyn-cast))
(define (bad) (let ((resource (Resource "r"))) (integer "bad") (panic "unreachable")))
