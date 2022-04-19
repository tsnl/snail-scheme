; recursion

(define (rec-chk x)
  (if (= x 0) 
    0
    (if (= x 1)
        100
        (rec-chk 0))))

(rec-chk 0)
(rec-chk 1)
(rec-chk 2)

