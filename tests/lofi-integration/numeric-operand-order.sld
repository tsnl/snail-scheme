(import
 (lofi base))
(def log
     (ref (ann 0 I64)))
(def record
     (lambda (digit)
       (begin
         (ref-set! log (+ (* (ref-get log) (ann 10 I64)) digit))
         (i64->f64 digit))))
(def operator
     (lambda ()
       (begin
         (record (ann 3 I64))
         +)))
(def result
     ((operator) (record (ann 1 I64)) (record (ann 2 I64))))
(if (if (= result 3.0) (= (ref-get log) (ann 123 I64)) #f) (ann 42 I64) (unreachable))
