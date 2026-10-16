(import (lofi base))
(define-overload add-two (-> I64 I64) implementation)
(def answer
     (add-two (ann 40 I64)))
(def implementation
     (lambda (value) (+ value (ann 2 I64))))
answer
