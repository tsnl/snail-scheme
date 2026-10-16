(import (lofi base))
(def Box (datatype ( T) (box (value T unbox))))
(def make
     box)
(def read
     unbox)
(def apply1
     (lambda (f x) (f x)))
(+ (apply1 read (apply1 make (ann 34 I64))) (f64->i64 (read (make 3.5))))
