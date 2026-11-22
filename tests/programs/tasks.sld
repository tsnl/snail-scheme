(import
 (snail core base)
 (snail core io)
 (snail shell task))

(effect Label ((label (Fn → String))))

(define (child (out OutputPort)) (→ Unit) (! mut Label)
  (write-line out (string-append (label) " starts"))
  (yield)
  (write-line out (string-append (label) " resumes"))
  (sleep 1)
  (write-line out (string-append (label) " ends")))

(define (main (out OutputPort)) (→ Unit) (! mut)
  (handle Label ((label (lambda () "first")))
    (dispatch (lambda () (child out))))
  (handle Label ((label (lambda () "second")))
    (dispatch (lambda () (child out))))
  (write-line out "main returns")
  (unit))
