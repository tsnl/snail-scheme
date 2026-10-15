(import (snail strict))
(define-data First (first))
(define-data Second (second))
(match (first) ((first) 1) ((second) 2))
