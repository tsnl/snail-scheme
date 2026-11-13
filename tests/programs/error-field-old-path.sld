(import
 (snail core base))

(struct Point
  ((x I64)))

(define main
  (lambda ()
    (::x (Point 1))
    (unit)))
