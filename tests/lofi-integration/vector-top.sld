(import (lofi base))
(def original
     (make-vector (ann 2 I64) (ann 0 I64)))
(def hidden
     (ann original Any))
(def recovered
     (ann hidden (Vector I64)))
(vector-set! recovered (ann 1 I64) (ann 42 I64))
(if (vector-eq? original recovered) (vector-ref original (ann 1 I64)) (unreachable))
