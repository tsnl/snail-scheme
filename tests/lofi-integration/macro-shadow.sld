(import
 (lofi primitive))
(define-syntax increment (syntax-rules () ((_ value) 999)))
((lambda (increment) (increment 41)) (lambda (value) (i32-add value 1)))
