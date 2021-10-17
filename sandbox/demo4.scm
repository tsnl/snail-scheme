; testing builtin functions:
;   e.g. cons, =, eq?, eqv?, equal?

(define w (cons 0 (cons 1 (cons 2 (cons 3 ())))))
(define wa (car w))
(define wd (cdr w))

'(1 2 3 4 5 6)

(= 1 2)

(= 1 1)
(eqv? '(1 2) '(1 2))
(define x '(1 2))
(eq? x x)
(eqv? x x)
(equal? '(1 2 3 4 5) '(1 2 3 4))

(define animals
    (list
        (list 'zebra 4500 3200)
        (list 'horse 4800 3500)))
