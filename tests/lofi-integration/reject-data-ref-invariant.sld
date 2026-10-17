(import (lofi base))
(def Cell (datatype ( T) (cell (value (Ref T) cell-ref))))
(def x
     (cell (ref (ann 1 I64))))
(def alias
     x)
(ref-set! (cell-ref alias) #t)
(ref-get (cell-ref x))
