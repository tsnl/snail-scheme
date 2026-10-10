(define-library (scheme process-context)
  (export command-line exit get-environment-variable)
  (import (only (snail-scheme core) command-line exit get-environment-variable)))
