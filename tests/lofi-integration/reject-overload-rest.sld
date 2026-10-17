(import
 (lofi base))
(define-overload select (-> I64 (Rest I64) I64) (lambda (value . rest) value))
0
