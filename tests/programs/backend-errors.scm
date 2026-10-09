(import (scheme base) (scheme process-context))

;; Compile the shared bootstrap once, then exercise independent failure paths.
(case (string->symbol (cadr (command-line)))
  ((arity) ((lambda (x) x)))
  ((uninitialized) (letrec ((x x)) x))
  ((values) (cons (values 1 2) '()))
  ((overflow) (+ 9223372036854775807 1))
  (else (error "unknown backend error case")))
