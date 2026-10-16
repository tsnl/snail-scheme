(import (lofi primitive))
(def recur (All (T) (-> T T))
     (lambda (value) (if #t (ann 42 I64) (recur value))))
(ann 42 I64)
