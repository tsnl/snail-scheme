(define (-1+ x) (- x 1))
(define (-2+ x) (- x 2))

(define (f x)
    (if (or (= x 0) (= x 1))
        x
        (+ (f (-1+ x) (-2+ x)))))
