(import (lofi base))
(def make-adder
     (lambda (amount) (lambda (x) (+ amount x))))
((make-adder (ann 40 I64)) (ann 2 I64))
