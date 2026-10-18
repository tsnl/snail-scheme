(import
 (lofi base))
(define-overload promote (-> I64 F64) i64->f64)

(def combine (All (A B R) (requires (+ (-> A B R))) (-> A B R))
     (lambda (left right) (+ left right)))

(def discard (All (A B R) (requires (+ (-> A B R))) (-> A B Unit))
     (lambda (left right)
       (begin (+ left right) (unit))))
(def nested
     (lambda (value) (+ (promote value) (combine value 2.0))))
(discard (ann 20 I64) 22.0)
(if (= (nested (ann 20 I64)) 42.0) (ann 42 I64) (unreachable))
