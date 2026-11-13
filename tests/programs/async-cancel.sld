(import
 (snail core base)
 (only (snail core forms) host)
 (snail core io)
 (snail shell task)
 (snail shell future)
 (snail shell async))

(struct Resource
  ((name String)))
(instance (Drop (! output-port) Resource)
  (define (drop (resource Resource)) (→ Unit) (! output-port)
    (match resource ((Resource name) (write-line (string-append "released " name))))))

(define (main) (→ Unit) (! mut host output-port completion)
  ;; Both endpoints are in suspended tasks. Detaching the scheduler's queues
  ;; before dropping either task makes the completion wake harmless.
  (let ((scheduler (make-scheduler)))
    (dispatch-in scheduler
                 (once (lambda ()
                         (let* ((held (Resource "suspended"))
                                (future (dispatch (once (lambda () (sleep 100000) held)))))
                           (dispatch-local (once (lambda () (drop (await-future future)))))
                           (unit)))))
    (tasks-turn scheduler 0)
    (tasks-turn scheduler 0)
    (tasks-close! scheduler)
    (tasks-close! scheduler)
    (write-line "suspended tasks closed"))
  ;; An external receiver observes abandonment when its queued producer is
  ;; canceled. Its registered one-shot callback is invoked exactly once.
  (let ((scheduler (make-scheduler)))
    (match (ann (make-promise) (Pair (Promise I64) (Future I64)))
      ((Pair promise future)
       (let* ((held (Resource "during close"))
              (future (on-ready future (once (lambda () (drop held))))))
         (dispatch-in scheduler (once (lambda () (drop (fulfill promise 7)))))
         (tasks-close! scheduler)
         (match (poll future)
           ((Ready (Abandoned)) (write-line "queued producer abandoned"))
           ((Ready (Completed _)) (panic "canceled work ran"))
           ((Pending future) (drop future) (panic "canceled producer stayed pending")))))))
  (unit))
