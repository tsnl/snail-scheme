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
(define (observe) (→ Unit) (! output-port signals tasks)
  (match (termination)
    ((Terminate) (write-line "observed Terminate"))
    ((Interrupt) (write-line "observed Interrupt"))
    ((Kill) (panic "SIGKILL cannot be observed"))))

(define (spin) (→ Unit)
  (spin))

(define (main) (→ Unit) (! host mut output-port signals tasks)

  (if (member? "wait" (command-line))
      (dispatch observe)
      (dispatch (lambda () (sleep 30000))))
  (dispatch (lambda ()
              (write-line "ready")
              (if (member? "busy" (command-line)) (spin) (unit))))
  (unit))
