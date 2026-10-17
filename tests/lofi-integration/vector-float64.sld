(import (lofi base))
(def values
     (vector 1.25 2.5))
(def copy
     (vector-append (empty-vector) values (vector-copy values)))
(f64-add (vector-ref copy (ann 0 I64)) (vector-ref copy (ann 3 I64)))
