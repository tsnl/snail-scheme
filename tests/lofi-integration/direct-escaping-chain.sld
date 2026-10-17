(import
 (lofi base))

(def make-probe
     (lambda ()
       (begin
         (def first
              (lambda () (second)))
         (def second
              (lambda () (lambda () (vector-ref later (ann 0 I64)))))
         (def saved
              (first))
         (def later
              (make-vector (ann 1 I64) (ann 42 I64)))
         saved)))

((make-probe))
