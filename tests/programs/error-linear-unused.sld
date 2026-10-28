(import
 (snail core base))

;; A linear value must be used: the compiler inserts no drop.
(let ((work (once (lambda () (unit)))))
  (unit))
