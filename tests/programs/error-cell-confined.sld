(import
 (snail core base))

;; Writing a parameter's cell mutates storage from outside, which a
;; function whose type forbids mut may not do.
(define (reset (cell (Ref I64))) (→ Unit)
  (set! (ref-get cell) 0))

(reset (ref 3))
