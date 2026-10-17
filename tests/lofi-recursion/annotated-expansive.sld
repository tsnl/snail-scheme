(import
 (lofi primitive))
(def cell (ref (lambda (value) (invoke value))))
(def invoke (All (T) (-> T T)) (lambda (value) ((ref-get cell) value)))
(ann 42 I64)
