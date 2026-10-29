(import
 (snail core base))

;; Reading a mutable field leaves its content in place, so linear content
;; must be swapped out instead.
(struct Holder
  ((work mut (Once (-> Unit)))))

(let ((holder (Holder (once (lambda () (unit))))))
  (call-once (Holder-work holder)))
