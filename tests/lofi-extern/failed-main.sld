(import
 (lofi base))
(define-extern mark "probe" "mark" (-> I32 Unit))

(def worker (-> I32 I32)
     (lambda (value) value))
(mark (ann 8 I32))
(unreachable)
