(import
 (snail core base)
 (snail shell task))

;; Dispatched work runs later, on a turn of the scheduler, when the
;; handles it would yield to may have returned; it may yield only to tasks.
(effect Abort
  ((ctl abort (-> I64 I64))))

(: start (-> Unit ! mut))
(define (start)
  (handle Abort ((abort (lambda (value resume) (drop resume) (unit))))
    (dispatch-local (once (lambda () (abort 1) (unit))))))

(start)
