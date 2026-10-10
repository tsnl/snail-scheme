;; A frontend-only script that can itself be compiled as Scheme.
;; The script, not the compiler library, chooses this positional interface.
(import (scheme base) (scheme process-context) (snail-scheme compiler))
(apply source-file->wat-file (cdr (command-line)))
