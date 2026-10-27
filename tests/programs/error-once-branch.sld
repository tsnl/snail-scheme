(import
 (snail-core base))
(let ((work (once (lambda () (unit))))) (if #t (call-once work) (unit)) (call-once work))
