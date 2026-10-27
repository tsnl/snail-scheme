(import
 (snail-core base))
(define work (once (lambda () (unit))))
(call-once work)
