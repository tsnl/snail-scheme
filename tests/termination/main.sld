(import
 (snail core base)
 (only (snail core forms) host)
 (snail core io)
 (snail shell task)
 (snail shell process))

;; Run with `wait`, a task waits for termination. Tasks run in the order
;; they were dispatched, so it is waiting before the task after it prints
;; "ready": a signal after that is the waiter's to observe. Run without it,
;; no task waits, and a signal ends the program as it always has; with
;; `busy`, it does so while the task after "ready" computes without end.
(define (observe (signals Signals) (out OutputPort)) (→ Unit) (! mut tasks)
  (match (termination signals)
    ((Terminate) (write-line out "observed Terminate"))
    ((Interrupt) (write-line out "observed Interrupt"))
    ((Kill) (panic "SIGKILL cannot be observed"))))

(define (spin) (→ Unit)
  (spin))

(define (main (signals Signals) (out OutputPort)) (→ Unit) (! host mut tasks)

  (if (member? "wait" (command-line))
      (dispatch (lambda () (observe signals out)))
      (dispatch (lambda () (sleep 30000))))
  (dispatch (lambda ()
              (write-line out "ready")
              (if (member? "busy" (command-line)) (spin) (unit))))
  (unit))
