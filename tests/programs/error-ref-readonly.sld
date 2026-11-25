(import
 (snail core base))

(record Vec
  ((x I64)))
(define (bad (v (Ref Vec))) (→ Unit) (set! (● v x) 1))
(define (main) (→ Unit) (unit))
