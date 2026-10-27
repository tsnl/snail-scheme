(import
 (snail-core base)
 (snail-core task))

;; Dispatched work runs later, on a task's own stack, which the
;; dispatcher's handlers are not on.
(effect Abort
  ((ctl abort (-> I64 I64))))

(: start (-> Unit ! tasks))
(define (start)
  (handle Abort ((abort (lambda (value resume) (unit))))
    (dispatch-local (once (lambda () (abort 1) (unit))))))

(start)
