(import (scheme base) (only (lofi core) def ann I64))
(def value (ann 40 I64))
(define (add-two x) (+ x (ann 2 I64)))
(add-two value)
