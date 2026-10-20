(define-syntax bind (syntax-rules () ((_ name value) (def name value))))
((lambda ()
   (begin (bind bind (lambda (x y) x)) 0)))
