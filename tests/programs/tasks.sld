(import
 (snail core base)
 (snail core io)
 (snail shell task))

(effect Label ((label (dyn (Fn -> String)))))

(: child (impl (Fn -> Unit ! console tasks Label)))
(define (child)
  (write-line (string-append (label) " starts"))
  (yield)
  (write-line (string-append (label) " resumes"))
  (sleep 1)
  (write-line (string-append (label) " ends")))

(handle Label ((label (lambda () "first")))
  (dispatch-local (once child)))
(handle Label ((label (lambda () "second")))
  (dispatch-local (once child)))
(write-line "main returns")
