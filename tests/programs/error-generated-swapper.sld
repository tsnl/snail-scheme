(import
 (snail core base))

(record Cell
  ((value I64)))
(define (main) (→ Unit) (Cell-value-replace! (new Cell (value 1)) 2) (unit))
