(import
 (snail core base))

;; Writing a parameter's cell mutates storage from outside, which a
;; function whose type forbids mut may not do.
(: reset (-> (Ref I64) Unit))
(define (reset cell)
  (set! (ref-get cell) 0))

(reset (ref 3))
