(import
 (lofi primitive))
(define-syntax forward (syntax-rules () ((_ operator arguments) (operator . arguments))))
(forward i32-add (20 22))
