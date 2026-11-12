(import
 (snail core base))

(struct Point
  ((x I64)))

(define main
  (lambda ()
    (let ((point (ref (Point 1))))
      (with-borrow (borrowed point) (● borrowed x)))
    (unit)))
