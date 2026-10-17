(import
 (lofi primitive))
(def first (All (T) (-> T I64))
     (lambda (value) (if #t (ann 42 I64) (second (cons value (empty-list))))))
(def second (All (U) (-> U I64))
     (lambda (value) (first (cons value (empty-list)))))
(ann 42 I64)
