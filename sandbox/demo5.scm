; recursion

(define cons (lambda (a b) (p/invoke cons a b)))
(define car (lambda (pair) (p/invoke car pair)))
(define cdr (lambda (pair) (p/invoke cdr pair)))

(define = (lambda (a b) (p/invoke = a b)))
(define eq? (lambda (a b) (p/invoke eq? a b)))
(define eqv? (lambda (a b) (p/invoke eqv? a b)))
(define equal? (lambda (a b) (p/invoke equal? a b)))

(define displayln (lambda (it) (p/invoke displayln it)))

(define (rec-chk x)
  (if (= x 0) 
    0
    (if (= x 1)
        100
        (rec-chk 0))))

(displayln (rec-chk 0))
(displayln (rec-chk 1))
(displayln (rec-chk 2))

