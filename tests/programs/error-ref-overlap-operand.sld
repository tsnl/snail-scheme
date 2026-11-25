(import
 (snail core base))

(define (f (a (MutRef I64)) (v I64)) (→ Unit) (ref-set! a v))
(define (main) (→ Unit) (let ((x (ref-local 1))) (f (ref! x) (ref-get x)) (unit)))
