(import (lofi base))
(def cell
     (ref (ann 0 I64)))
(ref-set! cell #t)
(ref-get cell)
