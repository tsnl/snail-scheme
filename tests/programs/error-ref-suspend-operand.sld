(import
 (snail core base))

(define asking (→ (Prompt I64 I64)) (make-prompt))
(define (use (x (MutRef I64)) (v I64)) (→ Unit) (ref-set! x v))
(define (main) (→ Unit) (let ((x (ref-local 1))) (use (ref! x) (suspend asking 0)) (unit)))
