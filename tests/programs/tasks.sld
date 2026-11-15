(import
 (only (snail core forms) Host)
 (snail core base)
 (snail core io)
 (snail shell task))

(effect Label ((label (Fn → String))))

(define (child) (→ Unit) (! Output-port Tasks Label)
  (write-line (string-append (label) " starts"))
  (yield)
  (write-line (string-append (label) " resumes"))
  (sleep 1)
  (write-line (string-append (label) " ends")))

(define (main) (→ Unit) (! Host Mut Output-port Tasks)
  (handle Label ((label (lambda () "first")))
    (dispatch child))
  (handle Label ((label (lambda () "second")))
    (dispatch child))
  (write-line "main returns")
  (unit))
