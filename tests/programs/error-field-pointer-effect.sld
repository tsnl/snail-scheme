(import
 (snail core base))
(struct Point
  ((x I64)))
;; Learning the receiver after its lambda must still charge the read.
(define (read-x (point (Ref Point))) (→ I64)
  (let ((select (lambda (record) (● record x))))
    (select point)))
