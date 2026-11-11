(import
 (snail core base))

(: read-number (impl (Fn (Borrow I64) -> I64)))
(define (read-number value)
  (borrow-copy value))

(let ((cell (ref 1)))
  (with-borrow (borrowed (ref-get cell))
               (read-number borrowed)))
