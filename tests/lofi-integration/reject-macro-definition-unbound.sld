(import
 (lofi core))
(define-syntax m (syntax-rules () ((_) absent)))
((lambda (absent) (m)) 42)
