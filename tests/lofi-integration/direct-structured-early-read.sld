(import (lofi base))

(def digits
     (ref (ann 0 I64)))
(def record
     (lambda (digit)
       (begin
         (ref-set! digits (+ (* (ann 10 I64) (ref-get digits)) digit))
         digit)))

(def checked (-> I64)
     (lambda ()
       (begin
         (def early
              ((begin
                 (record (ann 3 I64))
                 (begin (let ignored (record (ann 4 I64))) later))
               (record (ann 1 I64)) (record (ann 2 I64))))
         (def later
              (lambda (left right) (+ left right)))
         early)))

(def observed (-> I64)
     (lambda () (ref-get digits)))

(ann 42 I64)
