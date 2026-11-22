(import
 (snail core base)
 (snail core io)
 (snail shell task))

;; A post wakes every waiting receiver, and the message goes to whichever
;; task asks first. `first` and `second` park; the producer's post wakes
;; both, but `third`, which was ready behind the producer, asks before
;; either runs and takes it. The woken receivers find nothing and wait
;; again, still in the order they began to wait.
(define (receive-one (out OutputPort) (mailbox (Mailbox String)) (name String))
  (→ Unit)
  (write-line out (string-append name " received " (mailbox-receive mailbox))))

(define (produce (mailbox (Mailbox String))) (→ Unit)
  (mailbox-post mailbox "one")
  (yield)
  (mailbox-post mailbox "two")
  (yield)
  (mailbox-post mailbox "three"))

(define (main (out OutputPort)) (→ Unit)
  (let ((mailbox (make-mailbox)))
    (dispatch (lambda () (receive-one out mailbox "first")))
    (dispatch (lambda () (receive-one out mailbox "second")))
    (dispatch (lambda () (produce mailbox)))
    (dispatch (lambda () (receive-one out mailbox "third"))))
  (unit))
