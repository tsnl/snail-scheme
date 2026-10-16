(import (lofi base))
(def Choice (datatype () (yes (value I64)) (no)))
(def count
     (ref (ann 0 I64)))
(def choose
     (lambda ()
       (begin (ref-set! count (+ (ref-get count) (ann 1 I64))) (yes (ann 11 I64)))))
(+ (match (choose) ((no) (ann 0 I64)) ((yes value) value)) (ref-get count))
