(import
 (snail core base)
 (snail core io)
 (snail shell task))

;; Receiving without waiting: an empty mailbox answers none at once, and
;; one with messages gives the oldest, leaving the rest for a receiver
;; that waits.
(define (tried (mailbox (Mailbox String))) (→ String)
  (match (mailbox-try-receive mailbox)
    ((Some message) message)
    ((None) "none")))

(define (main (mut Mut) (out OutputPort)) (→ Unit)
  (let ((mailbox (make-mailbox mut)))
    (write-line out (tried mailbox))
    (mailbox-post mailbox "first")
    (mailbox-post mailbox "second")
    (write-line out (tried mailbox))
    (dispatch (lambda () (write-line out (mailbox-receive mailbox))))
    (dispatch (lambda () (write-line out (tried mailbox)))))
  (unit))
