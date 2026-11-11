(import
 (snail core base)
 (snail core io)
 (snail shell task))

;; Two producers post into one mailbox and one consumer receives. The
;; consumer starts first and parks; each producer's first post comes
;; before its yield and its second after, so the messages arrive in the
;; order the producers ran, and the consumer receives them in that order:
;; one by waking from a park, the others already waiting in the queue.
(define (produce (mailbox (Mailbox String)) (name String)) (→ Unit) (! mut tasks)
  (mailbox-post mailbox (string-append name " 1"))
  (yield)
  (mailbox-post mailbox (string-append name " 2")))

(define (consume (mailbox (Mailbox String)) (count I64)) (→ Unit) (! console mut tasks)
  (when (> count 0)
    (write-line (string-append "received " (mailbox-receive mailbox)))
    (consume mailbox (- count 1))))

(let ((mailbox (make-mailbox)))
  (dispatch-local (once (lambda () (consume mailbox 4))))
  (dispatch-local (once (lambda () (produce mailbox "first"))))
  (dispatch-local (once (lambda () (produce mailbox "second"))))
  (write-line "main returns"))
