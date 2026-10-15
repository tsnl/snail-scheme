(import (snail strict))
(define-data Choice (some (value I64)) (none))
(define f (match (some 29) ((none) (lambda () 0)) ((some value) (lambda () value))))
(f)
