(import
 (lofi base)
 (lofi io))

;; A shared tail does not authorize a label absent from the context.
(: escape (All (A e) (-> (-> A ! console e) A ! e)))
(define (escape action) (action))
