(import
 (snail core base)
 (snail core io))
(struct Resource
  ((value I64)))
(instance (Drop (! output-port) Resource)
  (define (drop (resource Resource)) (→ Unit) (! output-port)
    (match resource ((Resource value) (display value) (newline)))))
(effect ReadValue ((read-value (Fn → I64))))
(handle ReadValue
    ((read-value (let ((resource (rc (Resource 12)))) (lambda () (● resource value)))))
  (display (read-value)) (newline)
  (display (read-value)) (newline))
(display 13) (newline)
