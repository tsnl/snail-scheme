(import
 (only (snail core forms) host)
 (snail core base)
 (snail core io)
 (snail shell task)
 (snail shell future)
 (snail shell async))

(define (main) (→ Unit) (! host mut output-port completion tasks)
  ;; Dispatch returns before the work starts. Await yields the task, not
  ;; the host stack, and hands the result to this continuation.
  (let ((future (dispatch (lambda ()
                            (write-line "work starts")
                            (yield)
                            "received"))))
    (write-line "dispatch returned")
    (match (poll future)
      ((Pending)
       (write-line "pending without running work")
       (write-line (await-future future)))
      ((Ready _) (unit))))
  ;; Result errors stay typed data and do not trap a task.
  (match (await-future (dispatch (lambda () (ann (Err "missing") (Result I64 String)))))
    ((Err message) (write-line message))
    ((Ok value) (write-line (show value))))
  ;; A timer wakes a parked task.
  (await-future (after 1))
  (write-line "timer")
  ;; Nothing observes this result; the work still runs to its end.
  (dispatch (lambda () (yield) (write-line "unobserved work finishes")))
  (unit))
