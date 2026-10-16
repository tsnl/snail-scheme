(import (lofi base))

(def worker (-> (Ref I32) I32)
     (lambda (x) (ref-get x)))
(ann 42 I64)
