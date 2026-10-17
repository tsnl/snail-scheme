(import (lofi base))
(def Tree (datatype () (leaf (value I64)) (branch (child Tree))))
(match (branch (leaf 1)) ((leaf value) value) ((branch (leaf value)) value))
