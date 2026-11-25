(import
 (snail core base))

(define (f (x Bool)) (→ I64)
  (match x
    (_ 1)
    (#t 2)))
