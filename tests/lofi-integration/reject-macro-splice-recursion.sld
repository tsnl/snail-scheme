(import
 (lofi core))
(define-syntax again (syntax-rules () ((_) (begin (again)))))
(again)
