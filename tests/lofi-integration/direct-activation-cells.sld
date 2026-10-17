(import
 (lofi base))

(def make-probe
     (lambda (count)
       (begin
         (def loop
              (lambda (n)
                (begin
                  (def owned
                       n)
                  (def hold
                       (lambda () (lambda () owned)))
                  (if (= n (ann 0 I64))
                      (hold)
                      (begin (let lofi-migration-let-1 (loop (- n (ann 1 I64)))) (let lofi-migration-let-2 (hold))
                             (let previous lofi-migration-let-1)
                             (let current lofi-migration-let-2)
                             (lambda () (+ (previous) (current))))))))
         (loop count))))

(+ (ann 6 I64) ((make-probe (ann 8 I64))))
