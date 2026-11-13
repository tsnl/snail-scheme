(import
 (snail core base)
 (snail core io))

(define answer (→ I64) (compute))

(define (compute) (→ I64) answer)

(define main
  (lambda ()
    (display answer)
    (unit)))
