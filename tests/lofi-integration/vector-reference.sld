(import (lofi base))
(def shared
     (ref (ann 0 I64)))
(def original
     (make-vector (ann 2 I64) shared))
(def copied
     (vector-copy original))
(def appended
     (vector-append (empty-vector) original copied (empty-vector)))
(ref-set! (vector-ref appended (ann 3 I64)) (ann 42 I64))
(vector-set! original (ann 0 I64) (ref (ann 7 I64)))
(if (if (ref-eq? (vector-ref copied (ann 0 I64)) (vector-ref original (ann 1 I64)))
        (if (= (ref-get (vector-ref original (ann 0 I64))) (ann 7 I64))
            (if (= (ref-get (vector-ref original (ann 1 I64))) (ann 42 I64)) (not (vector-eq? copied original)) #f)
            #f)
        #f)
    (ann 42 I64)
    (unreachable))
