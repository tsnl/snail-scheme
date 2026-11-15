(import
 (snail core base))

;; Only a value of a type with no cases, such as Never, can be matched with
;; no clauses: any other value would reach none.
(define (nothing (n I64)) (→ I64)
  (match n))
