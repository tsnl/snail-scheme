(import
 (snail core base))

;; Setting a mutable field discards its old content, which must not be
;; linear.
(struct Holder
  ((work mut (Once (-> Unit)))))

(let ((holder (Holder (once (lambda () (unit))))))
  (Holder-work-set! holder (once (lambda () (unit)))))
