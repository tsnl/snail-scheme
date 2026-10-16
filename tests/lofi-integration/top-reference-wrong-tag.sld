(import (lofi base))
(def cell
     (ref #t))
(def alias
     (ann (ann cell Any) (Ref I32)))
(ref-get alias)
