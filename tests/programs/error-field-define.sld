(import
 (snail core base)
 (snail core io))

;; The accessor name of a pure struct stays taken, as the field class
;; instance's method, so defining it is a duplicate.
(struct Point
  ((x I64)))

(define (Point-x (point Point)) (→ I64)
  (● point x))

(write-line (show (Point-x (Point 1))))
