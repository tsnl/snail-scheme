(import
 (lofi base))
(: duplicate (All (T) (-> T (Pair T T))))
(define (duplicate value) (Pair value value))
(duplicate (once (lambda () (unit))))
