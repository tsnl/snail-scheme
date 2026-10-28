(import
 (snail core base))

;; Only a value of a type with no cases, such as Never, can be matched with
;; no clauses: any other value would reach none.
(: nothing (-> I64 I64))
(define (nothing n)
  (match n))
