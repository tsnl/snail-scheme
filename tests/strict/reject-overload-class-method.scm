(import (snail strict))
(define-class (Select T) (: select (-> T T)))
(define-overload select (-> I64 I64) (lambda (value) value))
0
