(import (lofi primitive))
(define-extern record "instance.probe" "record" (-> I64 Unit))
(def observed (-> I64) (lambda () (ann 0 I64)))
(record (ann 1 I64))
(def first (begin (record (ann 2 I64)) second))
(def second (if #t (ann 42 I64) first))
(record (ann 3 I64))
second
