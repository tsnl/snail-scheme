(import
 (snail core base))

(effect audit ((note (Fn → Unit))))

(struct Resource
  ((name String)))

(instance (Drop (! audit) Resource)
  (define drop (lambda (resource) (note))))

(define main
  (lambda ()
    (handle dyn-cast ((conversion-failed (lambda (_) (unit))))
      (let ((resource (Resource "r")))
        (ann (ann "bad" Any) I64)
        (panic "unreachable")))
    (unit)))
