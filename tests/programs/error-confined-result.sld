(import
 (snail core base))

;; Building a cell is pure, but this function also writes the cell it
;; builds, and the cell would outlive the call.
(: leak (-> (Ref I64)))
(define (leak)
  (let ((cell (ref 0)))
    (ref-set! cell 1)
    cell))
