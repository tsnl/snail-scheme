(import
 (snail core base)
 (snail core io))

;; Former generated field names can be ordinary user functions.
(record Point
  ((x I64)))

(define (Point-x (point Point)) (→ I64)
  (● point x))

(define (main (out OutputPort)) (→ Unit)

  (write-line out (show (Point-x (new Point (x 1)))))
  (unit))
