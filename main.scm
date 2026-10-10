;; The native CLI platform initializes this module and invokes main once.
;; Compilation, artifact paths, and execution are ordinary library operations.
(import (scheme base) (scheme process-context)
        (snail-scheme cli) (snail-scheme installation))

(define (main)
  (let ((arguments (cdr (command-line))))
    (if (null? arguments) (error "usage: snail-scheme SCRIPT [ARGUMENT ...]"))
    (run-script (or (get-environment-variable "SNAIL_ROOT") installation-root)
                (car arguments) (cdr arguments))))
