(import
 (snail core base)
 (snail core io))

;; The accessor name of a pure struct stays taken, as the field class
;; instance's method, so defining it is a duplicate.
(struct Point
  ((x I64)))

(: Point-x (-> Point I64))
(define (Point-x point)
  (::x point))

(write-line (show (Point-x (Point 1))))
