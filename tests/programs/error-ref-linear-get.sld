(import
 (snail core base))
(let ((cell (ref (once (lambda () (unit))))))
  (call-once (ref-get cell)))
