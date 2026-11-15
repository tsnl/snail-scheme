(import
 (snail core base))

(record Cell
  ((value I64)))
(define (main) (→ Unit) (! mut)
  (let* ((cell (new Cell (value 0)))
         (memo (cache (lambda () (set! (● cell value) 1)))))
    (memo)))
