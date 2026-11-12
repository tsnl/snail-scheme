(import
 (snail core base))

(define (integer (value I64)) (→ I64) value)

(define main
  (lambda ()
    (integer "wrong")
    (unit)))
