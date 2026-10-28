(import
 (snail core base)
 (snail core io)
 (snail shell task)
 (snail shell process))

;; Run with `wait`, a task waits for termination, and main yields once so
;; that it is waiting before "ready" is printed: a signal after that is the
;; waiter's to observe. Run without it, no task waits, and a signal ends the
;; program as it always has.
(: observe (-> Unit ! console signals))
(define (observe)
  (match (termination)
    ((Terminate) (write-line "observed Terminate"))
    ((Interrupt) (write-line "observed Interrupt"))
    ((Kill) (panic "SIGKILL cannot be observed"))))

(if (member? "wait" (command-line))
    (dispatch-local (once observe))
    (dispatch-local (once (lambda () (sleep 30000)))))
(yield)
(write-line "ready")
