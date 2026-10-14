(import (snail strict))
(define-data First (first (value I64)))
(define-data Second (second (value I64)))
(match (ann (ann (second 1) Top) First) ((first value) value))
