(import (lofi base))
(define-overload select (All (T) (-> T T)) identity)
(def identity
     (lambda (x) x))
(if (if (select #t) (= (select (ann 42 I64)) (ann 42 I64)) #f) (ann 42 I64) (unreachable))
