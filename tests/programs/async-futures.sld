(import
 (snail core base)
 (snail core io)
 (snail shell task)
 (snail shell future)
 (snail shell async))

(struct Resource
  ((name String)))

(instance (Drop (! output-port) Resource)
  (define drop
    (lambda (resource) (match resource
                         ((Resource name) (write-line (string-append "released " name)))))))

;; Dispatch returns before the work starts. Await yields the task, not
;; the host stack, and transfers a linear result to this continuation.
(let ((future (dispatch (once (lambda ()
                                (write-line "work starts")
                                (yield)
                                (Resource "received"))))))
  (write-line "dispatch returned")
  (match (poll future)
    ((Pending future)
     (write-line "pending without running work")
     (match (await-future future)
       ((Completed resource) (drop resource))
       ((Abandoned) (panic "producer unexpectedly abandoned"))))
    ((Ready result) (drop result))))

;; Result errors stay typed data and do not trap a task.
(match (await-future (dispatch (once (lambda () (ann (Err "missing") (Result I64 String))))))
  ((Completed (Err message)) (write-line message))
  ((Completed (Ok value)) (write-line (show value)))
  ((Abandoned) (panic "producer unexpectedly abandoned")))

;; A timer wakes a parked task. An unobserved result still gets dropped.
(drop (await-future (after 1)))
(write-line "timer")
(drop (dispatch (once (lambda () (yield) (Resource "unobserved")))))
