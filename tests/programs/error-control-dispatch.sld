(import
 (snail core base)
 (snail shell task)
 (only (snail core forms) host))

;; Dispatched work runs later, on a turn of the scheduler, when the
;; handles it would yield to may have returned; it may yield only to tasks.
(effect Abort
  ((ctl abort (Fn I64 → I64))))

(define (start) (→ Unit) (! host mut tasks)
  (handle Abort ((abort (lambda (value resume) (drop resume) (unit))))
    (dispatch-local (once (lambda () (abort 1) (unit))))))

(define (main) (→ Unit) (! host mut tasks)

  (start)
  (unit))
