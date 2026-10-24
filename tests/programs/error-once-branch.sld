(import
 (lofi base))
(let ((work (once (lambda () (unit))))) (if #t (call-once work) (unit)) (call-once work))
