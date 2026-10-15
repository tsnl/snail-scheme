(import (snail strict))
(define-data Choice (live) (dead (impossible Never dead-value)))
(dead-value (live))
