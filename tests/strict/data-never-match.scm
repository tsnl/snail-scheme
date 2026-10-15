(import (snail strict))
(define-data Choice (left) (right))
(match (left) ((left) (unreachable)) ((right) (unreachable)))
