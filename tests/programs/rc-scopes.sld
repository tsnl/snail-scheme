(import
 (snail core base)
 (snail core io))

(struct Resource
  ((value I64)))

(instance (Drop (! output-port) Resource)
  (define (drop (resource Resource)) (→ Unit) (! output-port)
    (match resource ((Resource value) (display value) (newline)))))

(define (main) (→ Unit) (! mut output-port)
  (let ((resource (rc (Resource 1))))
    (let ((alias resource))
      (set! (● alias value) 2)
      (display (● resource value))
      (newline))
    (display 3)
    (newline))
  (display 4)
  (newline)
  (unit))
