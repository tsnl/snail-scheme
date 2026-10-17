(import (lofi base))

(def exercise
     (lambda ()
       (begin
         (def count
              (ref (ann 0 I64)))
         (def loop (-> I64 Unit)
              (lambda (remaining)
                (begin
                  (if (> remaining (ann 0 I64))
                      (begin
                        ((begin (let next (- remaining (ann 1 I64)))
                                (begin
                                  (def repeat
                                       (lambda ()
                                         (begin
                                           (ref-set! count (+ (ref-get count) (ann 1 I64)))
                                           ((begin loop) next))))
                                  repeat)))
                        (unit))
                      (unit))
                  (unit))))
         (def add-first (-> I64 (Rest I64) I64)
              (lambda (first . remaining) (+ first (car remaining))))
         (loop (ann 100000 I64))
         (begin
           (def again
                (lambda (remaining)
                  (if (= remaining (ann 0 I64))
                      (if (= (ref-get count) (ann 100000 I64)) ((begin add-first) (ann 40 I64) (ann 2 I64) (ann 99 I64)) (ann 0 I64))
                      ((begin again) (- remaining (ann 1 I64))))))
           (again (ann 100000 I64))))))

(exercise)
