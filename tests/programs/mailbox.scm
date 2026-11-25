(import
 (snail core base)
 (snail core io)
 (snail shell task))

;; Two producers post into one mailbox and one consumer receives. The
;; consumer starts first and parks; each producer's first post comes
;; before its yield and its second after, so the messages arrive in the
;; order the producers ran, and the consumer receives them in that order:
;; one by waking from a park, the others already waiting in the queue.
(define (produce (mailbox (Mailbox String)) (name String)) (→ Unit)
  (mailbox-post mailbox (string-append name " 1"))
  (yield)
  (mailbox-post mailbox (string-append name " 2")))

(define (consume (out OutputPort) (mailbox (Mailbox String)) (count I64))
  (→ Unit)
  (when (> count 0)
    (write-line out (string-append "received " (mailbox-receive mailbox)))
    (consume out mailbox (- count 1))))

(define (main (out OutputPort)) (→ Unit)

  (let ((mailbox (make-mailbox)))
    (dispatch (lambda () (consume out mailbox 4)))
    (dispatch (lambda () (produce mailbox "first")))
    (dispatch (lambda () (produce mailbox "second")))
    (write-line out "main returns"))
  (unit))
