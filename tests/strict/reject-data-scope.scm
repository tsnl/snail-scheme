(import (snail strict))
(define-data Box (box (value I64 unbox)))
(define outer (box 8))
(let () (define-data Box (box (value I64 unbox))) (unbox outer))
