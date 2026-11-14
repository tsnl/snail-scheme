(import
 (snail core base))

;; A path names a field the record's type does not have.
(record Point
  ((x I64)
   (y I64)))

(define main
  (lambda ()
    (● (new Point (x 1) (y 2)) z)
    (unit)))
