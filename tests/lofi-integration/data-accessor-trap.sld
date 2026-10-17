(import (lofi base))
(def Choice (datatype () (left (value I64 left-value)) (right (value I64 right-value))))
(left-value (right (ann 42 I64)))
