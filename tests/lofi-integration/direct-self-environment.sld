;; Self calls retain the environment of their own captured activation.
;; Alias and nested-closure calls still select the called closure environment.

(import (lofi base))

(def make-probe
     (lambda (seed)
       (begin
         (def state (ref seed))
         (def loop
              (lambda (n)
                (begin
                  (def nested (lambda () (loop (- n (ann 1 I64)))))
                  (if (= n (ann 0 I64))
                      (ref-get state)
                      (begin
                        (ref-set! state (+ (ref-get state) (ann 1 I64)))
                        (if (= n (ann 2 I64)) (nested) (loop (- n (ann 1 I64)))))))))
         loop)))

(def first (make-probe (ann 10 I64)))
(def second (make-probe (ann 20 I64)))
(def alias first)

(def generic (All (A) (-> I64 A A))
     (lambda (n value)
       (if (= n (ann 0 I64)) value (generic (- n (ann 1 I64)) value))))

(def sum-from
     (lambda (seed)
       (begin
         (def sum
              (lambda (n)
                (if (= n (ann 0 I64)) seed (+ (ann 1 I64) (sum (- n (ann 1 I64)))))))
         sum)))

(def sum (sum-from (ann 39 I64)))

(if (= (first (ann 3 I64)) (ann 13 I64))
    (if (= (second (ann 2 I64)) (ann 22 I64))
        (if (= (alias (ann 2 I64)) (ann 15 I64))
            (if (generic (ann 3 I64) #t)
                (if (= (generic (ann 3 I64) (ann 42 I64)) (ann 42 I64))
                    (if (= (sum (ann 3 I64)) (ann 42 I64)) (ann 42 I64) (ann 0 I64))
                    (ann 0 I64))
                (ann 0 I64))
            (ann 0 I64))
        (ann 0 I64))
    (ann 0 I64))
