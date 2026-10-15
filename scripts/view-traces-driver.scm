(import (scheme base) (scheme process-context) (snail-tools view-traces))
(exit (view-traces-main (cadr (command-line)) (cddr (command-line))))
