(import
 (lofi base))

;; The cell is the caller's.
(: poke (-> (Ref I64) Unit))
(define (poke cell)
  (ref-set! cell 1))
