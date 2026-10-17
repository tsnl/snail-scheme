(import
 (lofi base)
 (lofi io))
(def port (open-output-file "exhaust.txt"))
(write-string "buffered before exhaustion" port)
(def huge (make-vector (ann 1000000 I64) (ann 7 I64)))
(def read-huge (-> I64 I64)
     (lambda (index) (vector-ref huge index)))
(unit)
