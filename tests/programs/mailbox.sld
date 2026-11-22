(import
 (snail core base)
 (only (snail core forms) host)
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

(define (consume (out OutputPort) (mailbox (Mailbox String)) (count I64)) (→ Unit) (! host mut tasks)
  (when (> count 0)
    (write-line out (string-append "received " (mailbox-receive mailbox)))
    (consume out mailbox (- count 1))))

(define (main (out OutputPort)) (→ Unit) (! host mut tasks)

  (let ((mailbox (make-mailbox)))
    (dispatch (lambda () (consume out mailbox 4)))
    (dispatch (lambda () (produce mailbox "first")))
    (dispatch (lambda () (produce mailbox "second")))
    (write-line out "main returns"))
  (unit))
