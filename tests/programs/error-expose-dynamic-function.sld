(import
 (snail core base))

;; A program that loads a dynamic export checks its signature, the TypeId
;; of each parameter and of the result, and a function type's TypeId says
;; only that it is a function.
(define (twice (f (Fn I64 → I64)) (x I64)) (→ I64)
  (f (f x)))

(expose twice "twice" dynamic)
