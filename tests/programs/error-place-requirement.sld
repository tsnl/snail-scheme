(import
 (snail core base))
;; A completely generic receiver cannot establish a nominal slot.
(define (zero-x! (mut Mut) (cell R)) (→ Unit) (∀ (R))
  (set! mut (● cell x) 0))
