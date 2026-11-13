(define-library (lazy values)
  (export Cell cell alias bump next empty)
  (import
   (snail core base))
  (begin
    (struct Cell
      ((value I64)))
    (define cell (→ Cell) (Cell 0))
    (define alias (→ Cell) cell)
    (define empty (→ (List A)) (∀ (A)) (Nil))
    (define (bump) (→ I64) (! mut)
      (set! (● cell value) (+ 1 (● cell value)))
      (● cell value))
    (define next (→ (Fn → I64 ! mut))
      (let ((shared cell))
        (lambda ()
          (set! (● shared value) (+ 1 (● shared value)))
          (● shared value))))))
