(import (lofi base))
(def Select (typeclass ( T) (: select (-> T T))))
(define-overload select (-> I64 I64) (lambda (value) value))
0
