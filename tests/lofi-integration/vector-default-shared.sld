(import (lofi base))
(def count
     (ref (ann 0 I64)))
(def shared
     (ref (ann 0 I64)))
(def lofi-migration-instance-1 (instance (Default (Ref I64))
                                         (default (lambda ()
                                                    (begin
                                                      (ref-set! count (+ (ref-get count) (ann 1 I64)))
                                                      shared)))))
(def empty
     (ann (make-vector (ann 0 I64)) (Vector (Ref I64))))
(def values
     (ann (make-vector (ann 3 I64)) (Vector (Ref I64))))
(ref-set! (vector-ref values (ann 1 I64)) (ann 42 I64))
(if (if (= (ref-get count) (ann 3 I64))
        (if (= (vector-length empty) (ann 0 I64))
            (if (ref-eq? (vector-ref values (ann 0 I64)) (vector-ref values (ann 2 I64)))
                (if (= (ref-get (vector-ref values (ann 0 I64))) (ann 42 I64)) (= (ref-get shared) (ann 42 I64)) #f)
                #f)
            #f)
        #f)
    (ann 42 I64)
    (unreachable))
