(import
 (snail core base)
 (snail shell task)
 (only (snail core forms) Host))

;; Dispatched work runs later, on a turn of the scheduler, when the
;; handles it would yield to may have returned; it may yield only to tasks.
(effect Abort
  ((ctl abort (Fn I64 → I64))))

(define (start) (→ Unit) (! Host Mut Tasks)
  (handle Abort ((abort (lambda (value resume) (unit))))
    (dispatch (lambda () (abort 1) (unit)))))

(define (main) (→ Unit) (! Host Mut Tasks)

  (start)
  (unit))
