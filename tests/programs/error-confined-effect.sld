(import
 (snail core base))

;; An operation could hand the cell to a handler outside the call.
(effect Stash
  ((stash (dyn (Fn (Ref I64) → Unit)))))

(define (keep) (→ I64) (! Stash)
  (let ((cell (ref 1)))
    (stash cell)
    (ref-get cell)))
