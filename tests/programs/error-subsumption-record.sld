(import
 (snail core base))

;; A record's fields can be written, so its type arguments never widen:
;; a wider function written through the result would reach a reader of
;; the narrower pair.
(define (widen (pair (Pair I64 (Fn → Unit)))) (→ (Pair I64 (Fn → Unit ! mut)))
  pair)

(define (main) (→ Unit)
  (unit))
