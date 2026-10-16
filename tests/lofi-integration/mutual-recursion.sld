(import (lofi base))
(def even
     (lambda (n) (if (= n (ann 0 I64)) #t (odd (- n (ann 1 I64))))))
(def odd
     (lambda (n) (if (= n (ann 0 I64)) #f (even (- n (ann 1 I64))))))
(if (even (ann 100001 I64)) (ann 1 I64) (ann 0 I64))
