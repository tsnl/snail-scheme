(import (snail strict))
(: maker (-> I64 (All (T) (-> T T))))
(define (maker ignored) (lambda (value) value))
42
