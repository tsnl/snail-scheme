(import (snail strict))
(define-syntax boxed-value
  (syntax-rules ()
    ((_ value)
     (let () (define-data Box (box (item I64 unbox))) (unbox (box value))))))
(define-data Box (box (item Bool unbox)))
(if (unbox (box #t)) (+ (boxed-value 8) (boxed-value 9)) 0)
