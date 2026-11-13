(import
 (snail core base))

(struct (Cell T)
  ((value T)))

(define (integer (value (Cell I64))) (→ I64) (● value value))

(define dynamic (→ (Cell Any)) (Cell (ann 1 Any)))

(define main
  (lambda ()
    (integer dynamic)
    (unit)))
