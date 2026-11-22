(import
 (snail core base)
 (snail core io)
 (control catch)
 (control search))

(define (main (out OutputPort)) (→ Unit)
  ;; The suspension leaves `signal-negative`'s library, crosses this
  ;; program, and is caught in `first-signal`'s; `all-signals` resumes it
  ;; there.
  (display out (first-signal (lambda () (signal-negative out (list 1 2 -3 4)))))
  (newline out)
  (display out (first-signal (lambda () (signal-negative out (list 5)))))
  (newline out)
  (for-each (lambda (value) (display out value) (newline out))
            (all-signals (lambda () (signal-negative out (list 6 -7 8 -9)))))
  (unit))
