(import
 (lofi primitive))
(def recur (All (T) (-> T I64))
     (lambda (value) (if #t (ann 42 I64) (recur (cons value (empty-list))))))
(ann 42 I64)
