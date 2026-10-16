(define-library (macro generated-machine)
  (export Counter make-counter counter-value advance commands)
  (import (macro declaration-facade))
  (begin
    (define-machine Counter make-counter counter-value advance commands)))
