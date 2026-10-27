(import
 (snail-core base))
(let ((work (once (lambda () (unit))))) (call-once work) (call-once work))
