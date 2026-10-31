(import
 (snail core base))

;; A field read through a requirement may be computed, so it has no slot
;; to write.
(struct Point
  ((x I64)
   (y I64)))

(: zero-x! (All (R) (requires (::x R I64)) (-> (Ref R) Unit ! mut)))
(define (zero-x! cell)
  (set! (::x (ref-get cell)) 0))
