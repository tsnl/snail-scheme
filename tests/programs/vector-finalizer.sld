(import
 (snail core base)
 (snail core io))

(effect Log ((log-value (Fn I64 → Unit))))

(record Resource
  ((value I64)))

(instance (Drop (! Log) Resource)
  (define (drop (resource Resource)) (→ Unit) (! Log)
    (match resource ((Resource value) (log-value value)))))

(define (main) (→ Unit) (! mut output-port)
  (handle Log ((log-value (lambda (value) (display value) (newline))))
    (let ((items (make-vector 1 (rc (new Resource (value 1))))))
      (handle Log ((log-value (lambda (value)
                                (display (+ 100 (● (vector-ref items 0) value)))
                                (newline)
                                (set! (● (vector-ref items 0) value) 3))))
        (vector-set! items 0 (rc (new Resource (value 2)))))
      (display (vector-length items)) (newline))))
