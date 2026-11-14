(import
 (snail core base))

(record Point
  ((x I64)
   (y I64)))

(type Alias Point)

(define (bad) (→ Point)
  (new Alias (x 1) (y 2)))
