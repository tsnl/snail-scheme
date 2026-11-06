(import
 (snail core base))
(: read-cell (-> (Borrow (Ref I64)) I64 ! mut))
(define (read-cell borrowed) (ref-get borrowed))
