(import
 (lofi base))
(def exercise
     (lambda (seed)
       (begin
         (def even
              (lambda (n) (if (= n (ann 0 I64)) seed (odd (- n (ann 1 I64))))))
         (def odd
              (lambda (n) (if (= n (ann 0 I64)) (ann 0 I64) (even (- n (ann 1 I64))))))
         (even (ann 100000 I64)))))
(exercise (ann 42 I64))
