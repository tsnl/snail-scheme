(import (snail strict))
(define-data Choice (live (value I64)) (dead (impossible Never)))
(match (live 7) ((live value) value) ((dead impossible) impossible))
