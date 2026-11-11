(import
 (snail core base)
 (snail core io)
 (snail shell task)
 (snail shell future)
 (snail shell async))

(struct Resource
  ((name String)))

(instance (Drop (! console) Resource)
  (define (drop resource)
    (match resource
      ((Resource name) (write-line (string-append "released " name))))))

;; Both endpoints may be owned by suspended continuations. Shutdown must
;; detach its waiter queue before dropping a producer wakes its receiver.
(let* ((held (Resource "suspended"))
       (future (dispatch (once (lambda () (sleep 100000) held)))))
  (dispatch-local (once (lambda () (drop (await-future future)))))
  (yield)
  (tasks-close!)
  (write-line "suspended tasks closed"))

;; A future kept outside the canceled producer sees abandonment. A
;; completion observer attempting to dispatch during cleanup cannot leave
;; a new runnable task behind shutdown.
(: notified (impl (Fn -> Unit ! mut console)))
(define (notified)
  (let ((held (Resource "during close")))
    (dispatch-local (once (lambda () (drop held))))))

(let ((future
       (handle completion
           ((completed notified))
         (dispatch (once (lambda () 7))))))
  (tasks-close!)
  (match (poll future)
    ((Ready (Abandoned)) (write-line "queued producer abandoned"))
    ((Ready (Completed value)) (write-line (show value)))
    ((Pending future) (drop future) (panic "canceled producer stayed pending"))))
