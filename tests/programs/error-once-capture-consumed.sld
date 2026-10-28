(import
 (snail core base))

;; A closure that refers to a linear value consumed before it is built
;; would use it a second time.
(let* ((work (once (lambda () (unit))))
       (first (call-once work))
       (later (once (lambda () (call-once work)))))
  (call-once later))
