(import
 (snail core base))

(record Cell
  ((value I64)))
(enum Shape (Circle ((radius I64))) (Empty))

(define (read-record (cell Cell)) (→ I64) (Cell-value cell))
(define (read-case (circle Shape)) (→ I64) (Circle-radius circle))
(define (write-record (cell Cell)) (→ Unit) (Cell-value-set! cell 2))
(define (replace-record (cell Cell)) (→ Unit) (Cell-value-replace! cell 2) (unit))
(define (old-path (cell Cell)) (→ I64) (::value cell))
