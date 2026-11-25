(import
 (snail core base))

(define (f (x (Option I64))) (→ I64)
  (match x
    ((Some n) n)))
