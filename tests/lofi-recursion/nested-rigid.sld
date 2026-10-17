(import
 (lofi primitive))
(def recur (All (T) (-> I64 I64))
     (lambda (n)
       (begin
         (def inner (All (U) (-> U I64))
              (lambda (value) ((inst recur U) (ann 0 I64))))
         (if (i64-eq n (ann 0 I64)) (ann 42 I64) (inner (unit))))))
(ann 42 I64)
