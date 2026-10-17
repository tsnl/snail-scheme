(import (lofi base))
(def cell
     (ref 1.5))
(ref-set! cell (f64-add (ref-get cell) 2.25))
(ref-get cell)
