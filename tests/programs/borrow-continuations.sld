(import
 (snail core base)
 (snail core io)
 (snail shell task))

(effect Pause
  ((ctl pause (-> Unit))))

(struct Model
  ((title String))
  (deriving Move))

;; Its delimiter is inside this helper, so its continuation cannot capture
;; the caller's borrowed frame.
(: local-control (-> Unit))
(define (local-control)
  (handle Pause
      ((pause (lambda (resume) (resume (unit)))))
    (pause)))

(: work (-> (Borrow Model) (FnOnce Unit ! tasks console)))
(define (work model)
  (local-control)
  (let ((text (::title model)))
    (once (lambda ()
            (yield)
            (write-line text)))))

(let* ((model (Model "after the loan"))
       (task (with-borrow (borrowed model) (work borrowed))))
  (drop model)
  (task))
