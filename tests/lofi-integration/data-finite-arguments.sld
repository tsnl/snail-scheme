(import (lofi base))
(def Route (datatype ( T) (done (value T)) (next (rest (Route I64)))))
(def value
     (ann (next (done (ann 21 I64))) (Route Bool)))
(match value ((done flag) (if flag (ann 1 I64) (ann 0 I64)))
       ((next rest) (match rest ((done value) value) ((next again) (ann 0 I64)))))
