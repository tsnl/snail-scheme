(import
 (snail core base))

;; An Any holds a GC reference, and an Fn's code reference is not one.
(: twice (Fn I64 I64))
(define (twice x)
  (* 2 x))

(: boxed Any)
(define boxed
  (type-convert twice Any))
