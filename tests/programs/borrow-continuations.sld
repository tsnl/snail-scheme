(import
 (snail core base)
 (snail core io)
 (snail shell task))

(effect Pause
  ((ctl pause (Fn → Unit))))

(struct Model
  ((title String))
  (deriving Move))

;; Its delimiter is inside this helper, so its continuation cannot capture
;; the caller's borrowed frame.
(define (local-control) (→ Unit)
  (handle Pause
      ((pause (lambda (resume) (resume (unit)))))
    (pause)))

(define (work (model (Borrow Model))) (→ (FnOnce → Unit ! tasks output-port))
  (local-control)
  (let ((text (● model title)))
    (once (lambda ()
            (yield)
            (write-line text)))))

(let* ((model (Model "after the loan"))
       (task (with-borrow (borrowed model) (work borrowed))))
  (drop model)
  (task))
