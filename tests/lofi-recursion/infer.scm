;; Stop at inference: a recursive-type rejection must precede specialization.
(import
 (scheme base)
 (scheme cxr)
 (scheme process-context)
 (lofi compiler source-driver)
 (native chromium-trace))
(let ((arguments (cdr (command-line))))
  (with-chromium-trace-to (caddr arguments)
                          (lambda () (source-file->core (car arguments) (cadr arguments)))))
