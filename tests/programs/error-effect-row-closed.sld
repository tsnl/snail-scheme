(import
 (lofi base)
 (lofi io))

(: call (All (A e) (-> (-> A ! e) A ! e)))
(define (call action) (action))

(: escape (-> Unit))
(define (escape) (call (lambda () (write-line "escaped"))))
