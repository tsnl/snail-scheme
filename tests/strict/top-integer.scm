(import (snail strict))
(define (forget x) (ann x Top))
(ann (forget 4294967296) I64)
