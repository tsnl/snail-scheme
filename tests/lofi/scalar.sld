(import (lofi primitive))
(def increment (-> I64 I64)
     (lambda (value) (i64-add value (ann 1 I64))))
(increment (ann 41 I64))
