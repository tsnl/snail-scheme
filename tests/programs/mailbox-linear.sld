(import
 (snail core base)
 (snail core io)
 (snail shell task))

;; A mailbox may carry linear messages. The producer posts work items and
;; the consumer runs them: each moves into the mailbox and out to the one
;; receiver that takes it, so it runs exactly once. The consumer starts
;; first and parks, so the first item reaches it by waking it, and the
;; second is posted after the producer yields.
(type Work (FnOnce → Unit ! output-port))

(define (say (text String)) (→ Work)
  (once (lambda () (write-line text))))

(define (produce (mailbox (Mailbox Work))) (→ Unit) (! mut tasks)
  (mailbox-post mailbox (say "one"))
  (yield)
  (mailbox-post mailbox (say "two")))

(define (consume (mailbox (Mailbox Work)) (count I64)) (→ Unit) (! output-port mut tasks)
  (when (> count 0)
    (call-once (mailbox-receive mailbox))
    (consume mailbox (- count 1))))

(let ((mailbox (make-mailbox)))
  (dispatch-local (once (lambda () (consume mailbox 2))))
  (dispatch-local (once (lambda () (produce mailbox))))
  (write-line "main returns"))
