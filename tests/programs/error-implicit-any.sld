(import
 (snail core base))

(record (Cell T)
  ((value T)))

(define (integer (value I64)) (→ I64) value)
(define (integer-cell (cell (Cell I64))) (→ I64) (● cell value))
(define (apply-integer (function (Fn I64 → I64))) (→ I64) (function 1))
(define (dynamic (value Any)) (→ Any) value)

(define (box (value I64)) (→ Any) value)
(define (box-closure) (→ Any) (lambda () (unit)))
(define (box-generic (value T)) (→ Any) (∀ (T)) value)
(define (pass-function) (→ I64) (apply-integer dynamic))
(define (pass-cell (cell (Cell Any))) (→ I64) (integer-cell cell))
(define (pass-string) (→ I64) (integer "wrong"))
