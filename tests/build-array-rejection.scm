(import (scheme base) (scheme cxr) (scheme process-context)
        (snail-scheme compiler) (snail-scheme chromium-trace))
(define arguments (cdr (command-line)))
(with-chromium-trace-to
 (string-append (caddr arguments) ".trace.json")
 (lambda () (source-file->wat-file (car arguments) (cadr arguments) (caddr arguments))))
