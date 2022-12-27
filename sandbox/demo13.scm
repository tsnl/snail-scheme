; (define x 0)
; (define y x)
(define factorial (lambda (n) (if (p/invoke = n 0) 1 (p/invoke * n (p/invoke - n 1)))))
(define sumtorial (lambda (n) (if (p/invoke = n 0) 1 (p/invoke + n (p/invoke - n 1)))))

(p/invoke displayln (factorial 0))
(p/invoke displayln (factorial 1))
(p/invoke displayln (factorial 2))

(p/invoke displayln (sumtorial 0))
(p/invoke displayln (sumtorial 1))
(p/invoke displayln (sumtorial 2))
