; testing builtin functions:
;   e.g. cons, =, eq?, eqv?, equal?

(define cons (lambda (a b) (p/invoke cons a b)))
(define car (lambda (pair) (p/invoke car pair)))
(define cdr (lambda (pair) (p/invoke cdr pair)))

(define = (lambda (a b) (p/invoke = a b)))
(define eq? (lambda (a b) (p/invoke eq? a b)))
(define eqv? (lambda (a b) (p/invoke eqv? a b)))
(define equal? (lambda (a b) (p/invoke equal? a b)))

(define displayln (lambda (it) (p/invoke displayln it)))

(define w (cons 0 (cons 1 (cons 2 (cons 3 ())))))
(define wa (car w))
(define wd (cdr w))

(displayln '(1 2 3 4 5 6))

(displayln (= 1 2))

(= 1 1)
(eqv? '(1 2) '(1 2))
(define x '(1 2))
(eq? x x)
(eqv? x x)
(equal? '(1 2 3 4 5) '(1 2 3 4))

(define animals
    (p/invoke list
        (p/invoke list 'zebra 4500 3200)
        (p/invoke list 'horse 4800 3500)))

(displayln animals)
