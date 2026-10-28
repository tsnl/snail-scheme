(import
 (snail core base)
 (snail core io))

(: pure (-> I64 I64))
(define (pure x)
  (write-line "side effect")
  x)
