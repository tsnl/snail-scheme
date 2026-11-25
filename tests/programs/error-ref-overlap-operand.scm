(import
 (snail core base))

(define (f (a (MutRef I64)) (v I64) (b (Ref I64))) (→ Unit) (ref-set! a (+ v (ref-get b))))
(define (main) (→ Unit) (let ((x (ref-local 1))) (f (ref! x) (ref-get x) (ref x)) (unit)))
