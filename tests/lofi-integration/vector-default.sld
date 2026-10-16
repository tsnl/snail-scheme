(import (lofi base))
(def values
     (make-vector (ann 3 I64)))
(vector-set! values (ann 1 I64) (ann 42 I64))
(def floats
     (ann (make-vector (ann 2 I64)) (Vector F64)))
(def empty
     (ann (make-vector (ann 0 I64)) (Vector Bool)))

(def build (All (T) (=> ((Default T)) (-> I64 (Vector T))))
     (lambda (count) (make-vector count)))
(if (if (= (vector-ref values (ann 0 I64)) (ann 0 I64))
        (if (= (vector-ref values (ann 1 I64)) (ann 42 I64))
            (if (= (vector-ref values (ann 2 I64)) (ann 0 I64))
                (if (= (vector-ref floats (ann 0 I64)) 0.0)
                    (if (= (vector-length empty) (ann 0 I64)) (not (vector-ref (ann (build (ann 1 I64)) (Vector Bool)) (ann 0 I64))) #f)
                    #f)
                #f)
            #f)
        #f)
    (ann 42 I64)
    (unreachable))
