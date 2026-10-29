(import
 (snail core base))

;; An Fn is not a closure, and does not become one on its own; a lambda
;; around it is one.
(: twice (Fn I64 I64))
(define (twice x)
  (* 2 x))

(: doubled (List I64))
(define doubled
  (map twice (list 1 2 3)))
