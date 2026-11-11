(import
 (snail core base))

;; The cell is the caller's.
(define (poke (cell (Ref I64))) (→ Unit)
  (ref-set! cell 1))
