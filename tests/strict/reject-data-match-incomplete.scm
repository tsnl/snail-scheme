(import (snail strict))
(define-data Choice (yes) (no))
(match (yes) ((yes) 1))
