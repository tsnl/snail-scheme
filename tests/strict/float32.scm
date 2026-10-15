(import (snail strict))
(define (identity x) x)
(f32-add (identity (ann 1.5 F32)) (identity (ann 2.25 F32)))
