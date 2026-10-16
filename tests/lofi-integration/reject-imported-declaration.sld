;; Lofi rejects detached signatures as syntax. The original binding context is retained.
(import (lofi base))
(: vector-copy (-> I64 I64))
(vector-ref (vector-copy (vector 42)) 0)
