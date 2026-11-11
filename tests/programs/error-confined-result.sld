(import
 (snail core base))

;; Building a cell is pure, but this function also writes the cell it
;; builds, and the cell would outlive the call.
(define (leak) (→ (Ref I64))
  (let ((cell (ref 0)))
    (ref-set! cell 1)
    cell))
