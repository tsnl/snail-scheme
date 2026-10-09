(import (scheme base) (scheme process-context) (snail-scheme compiler))

;; This entry point is ordinary Scheme, so the host and generated executable
;; execute the same source. Switching the build to the latter is a later step.
(compiler-main (command-line))
