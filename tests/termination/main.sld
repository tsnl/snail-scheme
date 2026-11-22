(import
 (snail core base)
 (snail core io)
 (snail shell task)
 (snail shell process))

;; Run with `wait`, a task waits for termination. Tasks run in the order
;; they were dispatched, so it is waiting before the task after it prints
;; "ready": a signal after that is the waiter's to observe. Run without it,
;; no task waits, and a signal ends the program as it always has; with
;; `busy`, it does so while the task after "ready" computes without end.
(define (observe (signals Signals) (out OutputPort)) (→ Unit)
  (match ((● signals termination))
    ((Terminate) (write-line out "observed Terminate"))
    ((Interrupt) (write-line out "observed Interrupt"))
    ((Kill) (panic "SIGKILL cannot be observed"))))

(define (spin) (→ Unit)
  (spin))

(define (main (arguments Arguments) (signals Signals) (out OutputPort)) (→ Unit)

  (if (member? "wait" (command-line arguments))
      (dispatch (lambda () (observe signals out)))
      (dispatch (lambda () (sleep 30000))))
  (dispatch (lambda ()
              (write-line out "ready")
              (if (member? "busy" (command-line arguments)) (spin) (unit))))
  (unit))
