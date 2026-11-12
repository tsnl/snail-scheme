(import
 (snail core base))

;; A struct of two fields is two slots, so it cannot be an array's element.
(struct Point
  ((x I64)
   (y I64)))

(define main
  (lambda ()
    (make-array 2 (Point 1 2))
    (unit)))
