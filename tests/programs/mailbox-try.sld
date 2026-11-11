(import
 (snail core base)
 (snail core io)
 (snail shell task))

;; Receiving without waiting: an empty mailbox answers none at once, and
;; one with messages gives the oldest, leaving the rest for a receiver
;; that waits.
(define (tried (mailbox (Mailbox String))) (→ String) (! mut)
  (match (mailbox-try-receive mailbox)
    ((Some message) message)
    ((None) "none")))

(let ((mailbox (make-mailbox)))
  (write-line (tried mailbox))
  (mailbox-post mailbox "first")
  (mailbox-post mailbox "second")
  (write-line (tried mailbox))
  (dispatch-local (once (lambda () (write-line (mailbox-receive mailbox)))))
  (dispatch-local (once (lambda () (write-line (tried mailbox))))))
