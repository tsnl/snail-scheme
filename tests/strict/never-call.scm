(import (snail strict))
(define (stop) (unreachable))
(if #t 42 (stop))
