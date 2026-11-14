(import
 (snail core base))

(record Point
  ((x I64)))

(define main
  (lambda ()
    (::x (new Point (x 1)))
    (unit)))
