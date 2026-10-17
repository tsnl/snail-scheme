(import
 (lofi base))
(define-extern callback "probe" "callback" (-> Unit))

(def worker (-> I32 I32)
     (lambda (value) value))
(callback)
(ann 42 I64)
