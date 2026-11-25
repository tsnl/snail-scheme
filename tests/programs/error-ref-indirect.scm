(import
 (snail core base))

(define (read-it (x (Ref I64))) (→ I64) (ref-get x))

(define (indirect (x (Ref I64))) (→ I64)
  (let ((f read-it)) (f (ref x))))

(define (main) (→ Unit) (unit))
