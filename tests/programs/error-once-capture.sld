(import
 (snail-core base))
(let* ((work (once (lambda () (unit))))
       (twice (lambda () (call-once work))))
  (twice))
