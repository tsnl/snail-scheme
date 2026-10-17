(import
 (lofi base))

(def increment (-> I64 I64)
     (lambda (x) (+ x (ann 1 I64))))
(def erased
     (ann increment Any))
((ann erased (-> I64 I64)) (ann 41 I64))
