(import
 (lofi base))

(def add-first (-> I64 (List I64) I64)
     (lambda (first remaining)
       (if (null? remaining) first (+ first (car remaining)))))
(add-first (ann 42 I64) (list #t))
