(import
 (snail core base))

;; Each item that fails to check is reported, in source order: checking
;; goes on past an item that fails.
(define (first-wrong) (→ I64) "one")

(define (second-wrong) (→ I64) "two")

(define (main) (→ Unit)
  (unit))
