(import (lofi base))
(def plus
     +)
(def invoke
     (lambda (operation a b) (operation a b)))
(def choose
     (lambda (flag) (if flag + -)))
(def apply-vector
     (lambda (operation source)
       (vector (operation (vector-ref source (ann 0 I64)) (vector-ref source (ann 1 I64))))))
(def result
     (apply-vector plus (vector 1.5 2.25)))
(if (if (= (vector-ref result (ann 0 I64)) 3.75)
        (if (= (invoke (choose #f) (ann 44 I32) (ann 2 I32)) (ann 42 I32)) (invoke = 3.0 3.0) #f)
        #f)
    (invoke plus (ann 40 I64) (ann 2 I64))
    (unreachable))
