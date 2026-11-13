(import
 (snail core base))
(effect audit ((note (Fn → Unit))))
(struct Resource
  ((name String)))
(instance (Drop (! audit) Resource) (define drop (lambda (resource) (note))))
(define (integer (value Any)) (→ I64) (! dyn-cast) value)
(define (bad)
  (→ Unit)
  (! dyn-cast)
  (let ((resource (Resource "r"))) (integer "bad") (panic "unreachable")))
