(import (lofi base))
(def Box (datatype ( T) (box (value T unbox))))
(def original
     (ref (box (ann 65 I32))))
(def erased
     (ann original Any))
(unbox (ref-get (ann erased (Ref (Box Char)))))
