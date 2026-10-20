(import
 (lofi primitive))
(begin (let x 40) (define-syntax get (syntax-rules () ((_) (i32-add x 2)))) (let x 99) (get))
