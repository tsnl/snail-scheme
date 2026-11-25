(import
 (snail core base))

(define asking (→ (Prompt I64 I64)) (make-prompt))
(define (ask) (→ I64) (suspend asking 0))
(define (call (f (Fn → I64))) (→ I64) (f))
(define (use (x (Ref I64))) (→ I64) (let ((n (call ask))) (+ n (ref-get x))))
(define (main) (→ Unit) (let ((x (ref-local 1))) (use (ref x)) (unit)))
