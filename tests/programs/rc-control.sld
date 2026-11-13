(import
 (snail core base)
 (snail core io))

(record Resource
  ((value I64)))

(instance (Drop (! output-port) Resource)
  (define (drop (resource Resource)) (→ Unit) (! output-port)
    (match resource ((Resource value) (display value) (newline)))))

(effect Pause ((ctl pause (Fn → Unit))))

(define (work) (→ Unit) (! Pause mut output-port)
  (let ((resource (rc (new Resource (value 7)))))
    (pause)
    (display (● resource value)) (newline) (unit)))

(define (main) (→ Unit) (! mut output-port)
  (handle Pause ((pause (lambda (resume) (drop resume)))) (work))
  (display 8)
  (newline)
  (handle Pause ((pause (lambda (resume) (resume (unit))))) (work))
  (display 9)
  (newline)
  (unit))
