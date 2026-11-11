(import
 (snail core base))
(define (read-cell (borrowed (Borrow (Ref I64)))) (→ I64) (! mut) (ref-get borrowed))
