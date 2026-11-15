(import
 (snail core base))

(record Point
  ((x I64)
   (y I64)))

(define (bad) (→ Point)
  (new Point (x 1) (z 2)))
