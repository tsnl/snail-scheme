(import (lofi primitive))
(def cell (ref (empty-list)))
(def alias (All (T) (Ref (List T))) (ann cell (Ref (List T))))
(ann 42 I64)
