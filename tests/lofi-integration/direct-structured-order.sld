(import (lofi base))

(def digits
     (ref (ann 0 I64)))
(def record
     (lambda (digit)
       (begin
         (ref-set! digits (+ (* (ann 10 I64) (ref-get digits)) digit))
         digit)))
(def answer
     ((begin (let lofi-migration-let-1 (record (ann 3 I64))) (let lofi-migration-let-2 (record (ann 4 I64)))
             (let left lofi-migration-let-1)
             (let right lofi-migration-let-2)
             (begin
               (def middle
                    (record (ann 5 I64)))
               (def finish
                    (lambda (first second)
                      (begin
                        (record (ann 7 I64))
                        (+ (+ first second) (+ (+ left right) middle)))))
               (record (ann 6 I64))
               finish))
      (record (ann 1 I64)) (record (ann 2 I64))))

(if (if (= answer (ann 15 I64)) (= (ref-get digits) (ann 1234567 I64)) #f) (ann 42 I64) (ann 0 I64))
