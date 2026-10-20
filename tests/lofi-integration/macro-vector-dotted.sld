(import
 (lofi primitive))
(define-syntax unpack (syntax-rules () ((_ #(x (y . z))) (i32-add x (i32-add y z)))))
(unpack #(1 (2 . 39)))
