(import (lofi base))

(def digits
     (ref (ann 0 I64)))
(def visit
     (lambda (n)
       (if (> n (ann 0 I64))
           (begin
             (visit (- n (ann 1 I64)))
             (ref-set! digits (+ (* (ann 10 I64) (ref-get digits)) n))
             (unit))
           (unit))))

(visit (ann 9 I64))
(ref-get digits)
