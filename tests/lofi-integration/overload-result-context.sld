(import (lofi base))
(define-overload convert (-> I64 I64) (lambda (value) value))
(define-overload convert (-> I64 F64) i64->f64)
(def integer-view
     (ann convert (-> I64 I64)))
(def float-view
     (ann convert (-> I64 F64)))
(def value
     (convert (ann 42 I64)))
(if (if (= (ann (integer-view (ann 42 I64)) I64) (ann 42 I64))
        (if (= (ann (float-view (ann 42 I64)) F64) 42.0) (= (f64-add value 0.0) 42.0) #f)
        #f)
    (ann 42 I64)
    (unreachable))
