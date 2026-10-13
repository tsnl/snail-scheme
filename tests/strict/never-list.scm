(import (snail strict))
(define empty (ann '() (List Never)))
(if (null? empty) 42 (begin (car empty) 0))
