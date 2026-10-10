(import (scheme base) (scheme process-context))

;; Compile the shared bootstrap once, then exercise independent failure paths.
(case (string->symbol (cadr (command-line)))
  ((arity) ((lambda (x) x)))
  ((uninitialized) (letrec ((x x)) x))
  ((values) (cons (values 1 2) '()))
  ((numeric-type) (+ 1 #f))
  ((numeric-values) (+ 1 (values 2 3)))
  ((numeric-arity) (-))
  ((overflow) (+ 9223372036854775807 1))
  ((binary-range) (bytevector-copy (bytevector 1) 2))
  ((binary-utf8) (utf8->string (bytevector 255)))
  (else (error "unknown backend error case")))
