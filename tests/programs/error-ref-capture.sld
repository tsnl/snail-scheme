(import
 (snail core base))

(define (later (x (Ref I64))) (→ (Fn → I64)) (lambda () (ref-get x)))
(define (main) (→ Unit) (unit))
