(import
 (snail core base))

;; Reading a cell leaves its content in place, so linear content must be
;; swapped out instead.
(let ((holder (ref (once (lambda () (unit))))))
  (call-once (ref-get holder)))
