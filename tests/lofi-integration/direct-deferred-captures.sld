(import
 (lofi base))

(def exercise
     (lambda ()
       (begin
         (def choose
              (lambda (use-later?) (if use-later? (later) (ann 20 I64))))
         (def before
              (choose #f))
         (def later
              (lambda () (vector-ref payload (ann 0 I64))))
         (def payload
              (make-vector (ann 1 I64) (ann 22 I64)))
         (+ before (choose #t)))))

(exercise)
