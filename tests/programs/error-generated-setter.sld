(import
 (snail core base))

(record Cell
  ((value I64)))
(define (main) (→ Unit) (! mut) (Cell-value-set! (new Cell (value 1)) 2))
