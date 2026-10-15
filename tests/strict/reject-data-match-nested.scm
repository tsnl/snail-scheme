(import (snail strict))
(define-data Tree (leaf (value I64)) (branch (child Tree)))
(match (branch (leaf 1)) ((leaf value) value) ((branch (leaf value)) value))
