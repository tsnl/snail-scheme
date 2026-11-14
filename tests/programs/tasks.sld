(import
 (only (snail core forms) host)
 (snail core base)
 (snail core io)
 (snail shell task))

(effect Label ((label (Fn → String))))

(define (child) (→ Unit) (! output-port tasks Label)
  (write-line (string-append (label) " starts"))
  (yield)
  (write-line (string-append (label) " resumes"))
  (sleep 1)
  (write-line (string-append (label) " ends")))

(define (main) (→ Unit) (! host mut output-port tasks)
  (handle Label ((label (lambda () "first")))
    (dispatch child))
  (handle Label ((label (lambda () "second")))
    (dispatch child))
  (write-line "main returns")
  (unit))
