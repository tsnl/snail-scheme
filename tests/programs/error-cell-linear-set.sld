(import
 (snail core base))

;; Setting a cell discards its old content, which must not be linear.
(let ((holder (ref (once (lambda () (unit))))))
  (ref-set! holder (once (lambda () (unit)))))
