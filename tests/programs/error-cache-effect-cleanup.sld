(import
 (snail core base)
 (snail core io))

(record Resource
  ((value I64)))
(instance (Drop (! output-port) Resource)
  (define (drop (resource Resource)) (→ Unit) (! output-port)
    (match resource ((Resource value) (write-line (show value))))))

;; Finalization contributes effects even though the callback only reads a field.
(define (main) (→ Unit) (! mut output-port)
  (let* ((resource (rc (new Resource (value 1))))
         (memo (cache (lambda () (● resource value)))))
    (write-line (show (memo)))))
