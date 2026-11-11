(import
 (snail core base))

;; An Any holds a GC reference, and an Fn's code reference is not one.
(define twice (→ (fn I64 → I64))
  (lambda (x) (* 2 x)))

(define boxed (→ Any)
  (type-convert twice Any))
