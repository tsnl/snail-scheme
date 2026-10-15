(import (scheme base) (scheme process-context) (snail-tools generate-unicode))
(exit (generate-unicode-main (cadr (command-line)) (cddr (command-line))))
