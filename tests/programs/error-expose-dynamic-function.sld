(import
 (snail core base))

;; A program that loads a dynamic export checks its signature, the TypeId
;; of each parameter and of the result, and a function type's TypeId says
;; only that it is a function.
(: twice (-> (-> I64 I64) I64 I64))
(define (twice f x)
  (f (f x)))

(expose twice "twice" dynamic)
