;; Same library system and backend; imported forms select the Scheme surface.
(import (scheme base) (only (lofi primitive) i32->i64) (lofi io))
(define (fibonacci n)
  (if (< n 2) n (+ (fibonacci (- n 1)) (fibonacci (- n 2)))))
(write-i64 (i32->i64 (fibonacci 30)) (current-output-port))
(newline)
