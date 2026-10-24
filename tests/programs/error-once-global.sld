(import
 (lofi base))
(define work (once (lambda () (unit))))
(call-once work)
