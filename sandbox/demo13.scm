; (define x 0)
; (define y x)
(define factorial (lambda (n) (if (p/invoke = n 0) 1 (p/invoke * n (factorial (p/invoke - n 1))))))
(define sumtorial (lambda (n) (if (p/invoke = n 0) 1 (p/invoke + n (sumtorial (p/invoke - n 1))))))

(p/invoke displayln (factorial 15))

