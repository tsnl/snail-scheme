(import
 (snail core base))

(record Point
  ((x I64)
   (y I64)))

(define (bad) (→ Point)
  (new Point (y 2) (x "wrong")))
