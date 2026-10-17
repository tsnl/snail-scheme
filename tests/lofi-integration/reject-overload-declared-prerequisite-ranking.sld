(import (lofi base))
(def Identity (typeclass ( T) (: identity (-> T T))))
(define-overload choose (All (T) (=> ((Identity T)) (-> T T))) (lambda (value) (identity value)))
(define-overload choose (-> I64 I64) (lambda (value) (i64-add value (ann 0 I64))))
;; The missing Identity I64 proof cannot remove the generic competing row.
(choose (ann 42 I64))
