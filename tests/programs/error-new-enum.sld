(import
 (snail core base))

(record Point
  ((x I64)
   (y I64)))

(define (bad) (→ Point)
  (new Some (value 1)))
