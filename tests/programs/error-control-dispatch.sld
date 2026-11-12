(import
 (snail core base)
 (snail shell task))

;; Dispatched work runs later, on a turn of the scheduler, when the
;; handles it would yield to may have returned; it may yield only to tasks.
(effect Abort
  ((ctl abort (Fn I64 → I64))))

(define (start) (→ Unit) (! mut)
  (handle Abort ((abort (lambda (value resume) (drop resume) (unit))))
    (dispatch-local (once (lambda () (abort 1) (unit))))))

(define main
  (lambda ()
    (start)
    (unit)))
