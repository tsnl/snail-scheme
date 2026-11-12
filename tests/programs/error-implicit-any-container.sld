(import
 (snail core base))

(define (integer (value (Ref I64))) (→ I64) (! mut) (ref-get value))

(define dynamic (→ (Ref Any)) (ref (ann 1 Any)))

(define main
  (lambda ()
    (integer dynamic)
    (unit)))
