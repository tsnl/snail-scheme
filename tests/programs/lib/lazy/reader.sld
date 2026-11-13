(define-library (lazy reader)
  (export read-cell)
  (import
   (snail core base)
   (lazy values))
  (begin
    (define (read-cell) (→ I64) (● alias value))))
