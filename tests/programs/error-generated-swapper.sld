(import
 (snail core base))

(struct Cell
  ((value I64)))
(define (main) (→ Unit) (! mut) (Cell-value-replace! (Cell 1) 2) (unit))
