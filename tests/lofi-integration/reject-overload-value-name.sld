(import (lofi base))
(def select
     (lambda (value) value))
(define-overload select (-> I64 I64) (lambda (value) value))
(select 42)
