(import
 (lofi primitive))
(define-extern record "instance.probe" "record" (-> I64 Unit))
(record (ann 1 I64))
(def observed (-> I64) (lambda () (ann 0 I64)))
(def boxed Any 42)
(ann boxed I64)
