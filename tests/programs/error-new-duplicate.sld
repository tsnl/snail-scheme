(import
 (snail core base))

(record Point
  ((x I64)
   (y I64)))

(define (bad) (→ Point)
  (new Point (x 1) (x 2) (y 3)))
