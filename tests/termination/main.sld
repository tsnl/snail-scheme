(import
 (snail core base)
 (snail core io)
 (snail shell task)
 (snail shell process))

;; Run with `wait`, a task waits for termination. Tasks run in the order
;; they were dispatched, so it is waiting before the task after it prints
;; "ready": a signal after that is the waiter's to observe. Run without it,
;; no task waits, and a signal ends the program as it always has.
(: observe (-> Unit ! console signals tasks))
(define (observe)
  (match (termination)
    ((Terminate) (write-line "observed Terminate"))
    ((Interrupt) (write-line "observed Interrupt"))
    ((Kill) (panic "SIGKILL cannot be observed"))))

(if (member? "wait" (command-line))
    (dispatch-local (once observe))
    (dispatch-local (once (lambda () (sleep 30000)))))
(dispatch-local (once (lambda () (write-line "ready"))))
