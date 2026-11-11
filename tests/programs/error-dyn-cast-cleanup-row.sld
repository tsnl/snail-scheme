(import
 (snail core base))
(effect audit ((note (dyn (Fn -> Unit)))))
(struct Resource
  ((name String)))
(instance (Drop (! audit) Resource) (define (drop resource) (note)))
(: integer (impl (Fn Any -> I64 ! dyn-cast)))
(define (integer value) value)
(: bad (impl (Fn -> Unit ! dyn-cast)))
(define (bad) (let ((resource (Resource "r"))) (integer "bad") (panic "unreachable")))
