(define example
  (lambda (outer-outer)
    (lambda (outer)
      (lambda (inner)
        (p/invoke + outer-outer
          (p/invoke + outer inner))))))

(define print-sum
  (lambda (a b)
    (p/invoke displayln ((example a) b))))
(print-sum 1 2)
(print-sum 3 4)
