(import
 (snail core base))

;; A field read through a requirement may be computed, so it has no slot
;; to write.
(struct Point
  ((x I64)
   (y I64)))

(define (zero-x! (cell (Ref R))) (→ Unit) (! mut) (∀ R) (⊨ (::x R I64))
  (set! (::x (ref-get cell)) 0))
