(import
 (lofi base))
(define-overload select (-> I64 I64) (lambda (value) value))
(define-overload select (-> I64 I64 I64) i64-add)
(def alias
     select)
(def one
     (lambda (x) (alias x)))
(def two
     (lambda (x y) (alias x y)))
(if (if (= (one (ann 42 I64)) (ann 42 I64)) (= (two (ann 20 I64) (ann 22 I64)) (ann 42 I64)) #f) (ann 42 I64) (unreachable))
