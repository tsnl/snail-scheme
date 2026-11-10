(import
 (snail core base))

;; A fn is not a closure, and does not become one on its own; a lambda
;; around it is one.
(: twice (fn I64 -> I64))
(define (twice x)
  (* 2 x))

(: doubled (List I64))
(define doubled
  (map (ann twice (dyn (Fn I64 -> I64))) (list 1 2 3)))
