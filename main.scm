;; The native CLI platform initializes this module and invokes main once.
;; Compilation, artifact paths, and execution are ordinary library operations.
(import (scheme base) (scheme process-context)
        (snail-scheme native) (snail-scheme installation)
        (snail-scheme chromium-trace) (only (snail-scheme build-host) same-file?))

(define (main)
  (let ((arguments (cdr (command-line))))
    (if (null? arguments) (error "usage: snail-scheme SCRIPT [ARGUMENT ...]"))
    (if (same-file? (car arguments) (string-append (car arguments) ".trace.json"))
        (error "trace file must not replace script" (car arguments)))
    (with-chromium-trace-to (string-append (car arguments) ".trace.json")
                            (lambda ()
                              (run-script (or (get-environment-variable "SNAIL_ROOT") installation-root)
                                          (car arguments) (cdr arguments))))))
