(import
 (snail core base)
 (snail core io)
 (only (snail core primitive) inherit-handlers)
 (only (snail core forms) host))

(record Resource
  ((value I64)))

(instance (Drop (! output-port) Resource)
  (define (drop (resource Resource)) (→ Unit) (! output-port)
    (match resource ((Resource value) (display value) (newline)))))

(effect ReadValue ((read-value (Fn → I64))))

(define (job) (→ (FnOnce → Unit ! host)) (! mut output-port)
  (handle ReadValue
      ((read-value
        (let ((resource (rc (new Resource (value 12)))))
          (ann (lambda () (● resource value)) (Fn → I64 ! mut output-port)))))
    (inherit-handlers (once (lambda () (display (read-value)) (newline))))))

(define (main) (→ Unit) (! host mut output-port)
  (let ((work (job)))
    (display 20) (newline)
    (call-once work))
  (display 21)
  (newline)
  (let ((work (job)))
    (display 30) (newline)
    (drop work))
  (display 31)
  (newline)
  (unit))
