(import
 (lofi primitive))
(def first (lambda (value) (if #t (ann 42 I64) (second (cons value (empty-list))))))
(def second (lambda (value) (first (cons value (empty-list)))))
(ann 42 I64)
