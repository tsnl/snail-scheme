(import (lofi base))
(def values
     (make-vector (ann 2 I64) (ann (ann 42 I64) Any)))
(vector-set! values (ann 1 I64) (ann #t Any))
(if (ann (vector-ref values (ann 1 I64)) Bool) (ann (vector-ref values (ann 0 I64)) I64) (ann 0 I64))
