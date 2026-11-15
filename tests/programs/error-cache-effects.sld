(import
 (snail core base))

(record Cell
  ((value I64)))
(define (main) (→ Unit) (! Mut)
  (let* ((cell (new Cell (value 0)))
         (memo (cache (lambda () (set! (● cell value) 1)))))
    (memo)))
