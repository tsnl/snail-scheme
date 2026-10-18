(import
 (lofi base))

(def ignore (All (A R S) (requires (+ (-> A A R)) (+ (-> A A S))) (-> A Unit))
     (lambda (value)
       (begin (+ value value) (unit))))
(ann 42 I64)
