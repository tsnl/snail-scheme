(import (lofi base))
(def count
     (ref (ann 0 I64)))

(def calls (-> I64)
     (lambda () (ref-get count)))
(def lofi-migration-instance-1 (instance (Default (Ref I64))
                                         (default (lambda ()
                                                    (begin (ref-set! count (+ (ref-get count) (ann 1 I64))) (ref (ann 0 I64)))))))

(def allocate (-> I64)
     (lambda ()
       (begin
         (ann (make-vector (ann 4294967296 I64)) (Vector (Ref I64)))
         (ann 0 I64))))
(ann 42 I64)
