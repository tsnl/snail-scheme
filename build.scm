;; Bootstrap from the checkout, then rebuild using the resulting executable:
;;   chibi-scheme -I src build.scm
;;   build/snail-scheme build.scm
;; An optional argument selects the complete output filename.
(import (scheme base) (scheme process-context) (snail-scheme cli))

(define arguments (cdr (command-line)))
(if (> (length arguments) 1) (error "usage: build.scm [OUTPUT]"))
(define output (if (null? arguments) "build/snail-scheme" (car arguments)))
(build-interpreter "." output)
