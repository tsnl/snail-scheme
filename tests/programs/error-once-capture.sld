(import
 (lofi base))
(let* ((work (once (lambda () (unit)))) (twice (lambda () (call-once work)))) (twice))
