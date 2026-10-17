(import
 (lofi primitive))
(def recur (lambda (value) (if #t (ann 42 I64) (recur (cons value (empty-list))))))
(ann 42 I64)
