(import
 (snail core base))

;; A fn is not a closure, and does not become one on its own; a lambda
;; around it is one.
(define twice (→ (fn I64 → I64))
  (lambda (x) (* 2 x)))

(define doubled (→ (List I64))
  (map (ann twice (dyn (Fn I64 → I64))) (list 1 2 3)))
