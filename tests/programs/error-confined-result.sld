(import
 (snail-core base))

;; The new cell would outlive the call.
(: leak (-> (Ref I64)))
(define (leak)
  (ref 0))
