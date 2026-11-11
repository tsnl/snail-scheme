(import
 (snail core base))
(struct Point
  ((x I64)))
(let ((point (ref (Point 1))))
  (with-borrow (borrowed point) (● borrowed x)))
