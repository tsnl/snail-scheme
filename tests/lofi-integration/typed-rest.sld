(import
 (lofi base))

(def add-first (-> I64 (Rest I64) I64)
     (lambda (first . remaining)
       (if (null? remaining) first (+ first (car remaining)))))
(+ (add-first (ann 20 I64) (ann 2 I64) (ann 99 I64)) (add-first (ann 20 I64)))
