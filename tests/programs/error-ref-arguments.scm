(import
 (snail core base))

(define (update! (x (MutRef I64)) (y (MutRef I64))) (→ Unit)
  (ref-set! x (ref-get y)))

(define (twice (x (MutRef I64))) (→ Unit)
  (update! (ref! x) (ref! x)))

(define (missing-marker (x (MutRef I64)) (y (MutRef I64))) (→ Unit)
  (update! x (ref! y)))

(define (alias (x (Ref I64))) (→ I64)
  (let ((other x)) (ref-get other)))

(define (main) (→ Unit) (unit))
