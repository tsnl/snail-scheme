(import (lofi base))
(def state
     (ref (ann 40 I64)))
(def values
     (make-vector (ann 2 I64) (lambda (x) (+ (ref-get state) x))))
(def invoke
     (lambda (getter source) ((getter source (ann 1 I64)) (ann 2 I64))))
(invoke vector-ref values)
