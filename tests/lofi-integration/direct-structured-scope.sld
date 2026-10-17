(import
 (lofi base))

(def cell
     (ref (ann 0 I64)))
(def answer
     ((begin (let cell (ref (+ (ref-get cell) (ann 1 I64))))
             (begin
               (def finish
                    (lambda (amount)
                      (begin
                        (ref-set! cell (+ (ref-get cell) amount))
                        (ref-get cell))))
               finish))
      (begin (ref-set! cell (ann 40 I64)) (ann 1 I64))))

(if (if (= answer (ann 42 I64)) (= (ref-get cell) (ann 40 I64)) #f) (ann 42 I64) (ann 0 I64))
