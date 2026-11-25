(import
 (snail core base))

(define (read-it (x (Ref I64))) (→ I64) (ref-get x))
(expose read-it "read-it")
(define (main) (→ Unit) (unit))
