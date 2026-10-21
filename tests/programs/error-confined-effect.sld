(import
 (lofi base))

;; An operation could hand the cell to a handler outside the call.
(effect Stash
  ((stash (-> (Ref I64) Unit))))

(: keep (-> I64 ! Stash))
(define (keep)
  (let ((cell (ref 1)))
    (stash cell)
    (ref-get cell)))
