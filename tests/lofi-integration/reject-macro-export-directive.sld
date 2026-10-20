(import
 (lofi core))
(define-syntax expose (syntax-rules () ((_) (begin (export)))))
(expose)
42
