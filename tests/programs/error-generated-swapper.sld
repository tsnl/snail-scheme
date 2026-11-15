(import
 (snail core base))

(record Cell
  ((value I64)))
(define (main) (→ Unit) (! Mut) (cell-value-replace! (new Cell (value 1)) 2) (unit))
