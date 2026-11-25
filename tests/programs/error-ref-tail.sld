(import
 (snail core base))

(define (read-it (x (Ref I64))) (→ I64) (ref-get x))
(define (bad) (→ I64) (let ((local (ref-local 1))) (read-it (ref local))))
(define (main) (→ Unit) (unit))
