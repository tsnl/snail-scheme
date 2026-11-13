(import
 (snail core base)
 (snail core io))

(effect Log ((log-value (Fn I64 → Unit))))

(struct Resource
  ((value I64)))

(instance (Drop (! Log) Resource)
  (define (drop (resource Resource)) (→ Unit) (! Log)
    (match resource ((Resource value) (log-value value)))))

(define (main) (→ Unit) (! mut output-port)
  (handle Log ((log-value (lambda (value) (display value) (newline))))
    (let ((items (make-vector 1 (rc (Resource 1)))))
      (handle Log ((log-value (lambda (value)
                                (display (+ 100 (● (vector-ref items 0) value)))
                                (newline)
                                (vector-push! items (rc (Resource 3))))))
        (vector-set! items 0 (rc (Resource 2))))
      (display (vector-length items)) (newline))))
