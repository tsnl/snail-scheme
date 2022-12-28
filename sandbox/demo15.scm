(define global-1 (lambda () global-1))
(define global-2 (lambda () (global-1)))

(p/invoke displayln global-1)
(p/invoke displayln global-2)
(p/invoke displayln (global-1))
(p/invoke displayln (global-2))
