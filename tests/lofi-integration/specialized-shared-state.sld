(import (lofi base))
(def count
     (ref (ann 0 I64)))
(def counted
     (lambda (x)
       (begin
         (ref-set! count (+ (ref-get count) (ann 1 I64)))
         x)))
(counted (ann 42 I64))
(counted #t)
(ref-get count)
