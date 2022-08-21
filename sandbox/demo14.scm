;;; Testing lookups

(define add (lambda (a b) (p/invoke + a b)))

(define worker
  (lambda (x)
    (lambda (y)
      (add x y))))