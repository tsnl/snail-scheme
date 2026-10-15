(import (snail strict))
(define-data (Growing T) (end) (more (child (Growing (List T)))))
(ann (end) (Growing I64))
