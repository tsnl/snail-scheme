;; Stop at inference: a recursive-type rejection must precede specialization.
(import (scheme base) (scheme cxr) (scheme process-context)
        (snail-sfir source-driver) (snail-scheme chromium-trace))
(let ((arguments (cdr (command-line))))
  (with-chromium-trace-to (caddr arguments)
                          (lambda () (source-file->core (car arguments) (cadr arguments)))))
