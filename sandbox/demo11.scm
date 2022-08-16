;;; Demo and test of p/invoke

(define cons
  (lambda (a b)
    (p/invoke cons a b)))

(define l1 (cons 42 '()))
(define l2 (cons 43 l1))
(p/invoke displayln l2)