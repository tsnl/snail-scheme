(import (only (macro declarations) define-counter))
((lambda () (define-counter Counter make-counter counter-value advance commands)))
