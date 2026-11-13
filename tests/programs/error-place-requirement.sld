(import
 (snail core base))
;; A completely generic receiver cannot establish a nominal slot.
(define (zero-x! (cell R)) (→ Unit) (! mut) (∀ (R))
  (set! (● cell x) 0))
