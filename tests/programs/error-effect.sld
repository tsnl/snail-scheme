(import
 (lofi base)
 (lofi io))

(: pure (-> I64 I64))
(define (pure x)
  (write-line "side effect")
  x)
