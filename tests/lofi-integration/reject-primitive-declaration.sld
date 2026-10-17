;; Lofi rejects detached signatures as syntax. The original binding context is retained.
(import (lofi base))
(: i64-add (-> Bool Bool Bool))
(i64-add 20 22)
