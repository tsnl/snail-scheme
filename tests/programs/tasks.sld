(import
 (snail core base)
 (snail core io)
 (snail shell task))

(define (child (out OutputPort) (label String)) (→ Unit)
  (write-line out (string-append label " starts"))
  (yield)
  (write-line out (string-append label " resumes"))
  (sleep 1)
  (write-line out (string-append label " ends")))

(define (main (out OutputPort)) (→ Unit)
  (dispatch (lambda () (child out "first")))
  (dispatch (lambda () (child out "second")))
  (write-line out "main returns")
  (unit))
