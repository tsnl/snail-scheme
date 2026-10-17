(import (lofi base))
(def answer
     (add-two (ann 40 I64)))
(define-overload add-two (-> I64 I64) (lambda (value) (+ value (ann 2 I64))))
answer
