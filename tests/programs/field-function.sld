(import
 (snail core base)
 (snail core io))

;; Former generated field names can be ordinary user functions.
(struct Point
  ((x I64)))

(define (Point-x (point Point)) (→ I64)
  (● point x))

(define (main) (→ Unit) (! output-port)

  (write-line (show (Point-x (Point 1))))
  (unit))
