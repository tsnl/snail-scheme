; Without macros, only a limited subset of Scheme is supported by the interpreter.
; Here are some expressions in this subset.

; applying 'or2' to '#t' and '#f'-- expect '#f'
((lambda (x y) (if x x y)) #t #f)
((lambda (x y) (if x x y)) #t #t)
((lambda (x y) (if x x y)) #f #f)

(define x 42)
(define y x)
(define (or2 x y) (if x x y))
(define m (or2 #t #f))

(or2 #t #f)
(or2 #f #f)
(or2 #t #t)
(or2 #f #t)
