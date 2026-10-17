(import
 (lofi base))
(define-overload promote (-> I64 F64) i64->f64)
(def convert
     promote)

(def add (-> I64 F64 F64)
     +)
(def apply-twice
     (lambda (function value) (function (function value))))
(if (= (add (ann 20 I64) (convert (ann 22 I64))) 42.0) (ann 42 I64) (unreachable))
