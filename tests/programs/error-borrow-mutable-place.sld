(import
 (snail core base))

(define (read-number (value (Borrow I64))) (→ I64)
  (borrow-copy value))

(define main
  (lambda ()
    (let ((cell (ref 1)))
      (with-borrow (borrowed (ref-get cell))
                   (read-number borrowed)))
    (unit)))
