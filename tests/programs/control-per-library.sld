(import
 (snail core base)
 (snail core io)
 (control catch)
 (control search))

(define (main (out OutputPort)) (→ Unit) (! mut)
  ;; The yield leaves `signal-negative`'s module, crosses this one, and is
  ;; caught in `first-signal`'s, in a build linked from one module per
  ;; library as in a whole-program build; `all-signals` resumes it there.
  (display out (first-signal out (lambda () (signal-negative out (list 1 2 -3 4)))))
  (newline out)
  (display out (first-signal out (lambda () (signal-negative out (list 5)))))
  (newline out)
  (for-each (lambda (value) (display out value) (newline out))
            (all-signals out (lambda () (signal-negative out (list 6 -7 8 -9)))))
  (unit))
