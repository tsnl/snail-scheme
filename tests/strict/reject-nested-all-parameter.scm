(import (snail strict))
(: apply (-> (All (T) (-> T T)) I64))
(define (apply function) (function 42))
42
