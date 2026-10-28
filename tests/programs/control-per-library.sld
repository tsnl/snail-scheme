(import
 (snail core base)
 (snail core io)
 (control catch)
 (control search))

;; The yield leaves `signal-negative`'s module, crosses this one, and is
;; caught in `first-signal`'s, in a build linked from one module per
;; library as in a whole-program build; `all-signals` resumes it there.
(display (first-signal (lambda () (signal-negative (list 1 2 -3 4)))))
(newline)
(display (first-signal (lambda () (signal-negative (list 5)))))
(newline)
(for-each (lambda (value) (display value) (newline))
          (all-signals (lambda () (signal-negative (list 6 -7 8 -9)))))
