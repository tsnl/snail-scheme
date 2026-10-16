(import (lofi base))

(def count
     (ref (ann 0 I64)))

(def through (-> (-> I64 Unit) I64 Unit)
     (lambda (action n)
       (begin
         (action n)
         (unit)
         (unit))))

(def down (-> I64 Unit)
     (lambda (n)
       (if (> n (ann 0 I64))
           (begin
             (ref-set! count (+ (ref-get count) (ann 1 I64)))
             (up (- n (ann 1 I64)))
             (unit))
           (unit))))

(def up (-> I64 Unit)
     (lambda (n)
       (if (= n (ann 0 I64))
           (unit)
           (begin
             (ref-set! count (+ (ref-get count) (ann 1 I64)))
             (through down (- n (ann 1 I64)))
             (unit)))))

(down (ann 100000 I64))
(ref-get count)
