(import
 (snail core base)
 (snail core io)
 (snail shell task))

;; Receivers are served in the order they began to wait, even when a task
;; that was already ready asks before a woken receiver runs. `first` and
;; `second` park; the producer's post wakes `first`, and `third`, which
;; was ready behind the producer, asks before `first` runs. The message
;; is already `first`'s, so `third` waits behind `second`.
(: receive-one (-> (Mailbox String) String Unit ! console mut tasks))
(define (receive-one mailbox name)
  (write-line (string-append name " received " (mailbox-receive mailbox))))

(: produce (-> (Mailbox String) Unit ! mut tasks))
(define (produce mailbox)
  (mailbox-post mailbox "one")
  (yield)
  (mailbox-post mailbox "two")
  (yield)
  (mailbox-post mailbox "three"))

(let ((mailbox (make-mailbox)))
  (dispatch-local (once (lambda () (receive-one mailbox "first"))))
  (dispatch-local (once (lambda () (receive-one mailbox "second"))))
  (dispatch-local (once (lambda () (produce mailbox))))
  (dispatch-local (once (lambda () (receive-one mailbox "third")))))
