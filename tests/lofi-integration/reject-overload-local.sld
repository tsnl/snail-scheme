(import (lofi base))
(def outer
     (lambda (value)
       (begin
         (define-overload select (-> I64 I64) (lambda (value) value))
         (select value))))
(outer 42)
