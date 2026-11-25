(import
 (snail core base))

(define (f (a (Ref I64)) (b (MutRef I64))) (→ Unit) (ref-set! b (ref-get a)))
(define (main) (→ Unit) (let ((x (ref-local 1))) (f (ref x) (ref! x)) (unit)))
