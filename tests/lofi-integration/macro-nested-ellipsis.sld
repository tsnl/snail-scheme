(import
 (lofi primitive))
(define-syntax sum (syntax-rules () ((_) 0) ((_ x rest ...) (i32-add x (sum rest ...)))))
(define-syntax rows (syntax-rules () ((_ ((x ...) ...)) (sum (sum x ...) ...))))
(rows ((1 2) () (39)))
