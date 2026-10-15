(import (snail strict))
(define-class (Identity T) (: identity (-> T T)))
(define-overload choose (lambda (value) (identity value)))
(define-overload choose (lambda (value) (i64-add value 0)))
;; The missing Identity I64 proof cannot remove the generic competing row.
(choose 42)
