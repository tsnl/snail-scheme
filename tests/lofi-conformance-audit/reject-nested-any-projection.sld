(import (lofi primitive))
(def cell (ref (ann 42 I64)))
(def projected (All (T) (Ref T)) (ann (ann cell Any) (Ref T)))
(ann 42 I64)
