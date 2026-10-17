(import
 (lofi base))
(def exercise
     (lambda ()
       (begin
         (def delayed
              (lambda () (later (ann 42 I64))))
         (def later
              (lambda (x) x))
         (delayed))))
(exercise)
