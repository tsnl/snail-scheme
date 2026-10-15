(import (snail strict))
(define-data Box (box (value I64)))
(match (box 1) ((box) 0))
