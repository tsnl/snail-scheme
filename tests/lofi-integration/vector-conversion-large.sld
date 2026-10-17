(import
 (lofi base))
(def values
     (list->vector
      (begin
        (def loop
             (lambda (index result)
               (if (< index (ann 0 I64)) result (loop (- index (ann 1 I64)) (cons index result)))))
        (loop (ann 99999 I64) (empty-list )))))
(def joined
     (vector-append (vector (ann -1 I64)) values (vector (ann 100000 I64))))
(if (if (= (vector-length values) (ann 100000 I64))
        (if (= (vector-ref values (ann 0 I64)) (ann 0 I64))
            (if (= (vector-ref values (ann 99999 I64)) (ann 99999 I64))
                (if (= (vector-length joined) (ann 100002 I64))
                    (if (= (vector-ref joined (ann 0 I64)) (ann -1 I64))
                        (if (= (vector-ref joined (ann 1 I64)) (ann 0 I64))
                            (if (= (vector-ref joined (ann 100000 I64)) (ann 99999 I64)) (= (vector-ref joined (ann 100001 I64)) (ann 100000 I64)) #f)
                            #f)
                        #f)
                    #f)
                #f)
            #f)
        #f)
    (ann 42 I64)
    (unreachable))
