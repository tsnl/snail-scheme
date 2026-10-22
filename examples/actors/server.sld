(import
 (lofi base)
 (lofi actor)
 (ping))

(: serve (-> (Mailbox Ping Pong) Unit ! actors))
(define (serve mailbox)
  (let ((ping (receive mailbox)))
    (reply mailbox (Pong (string-append "pong: " (Ping-text ping))))))

(define-actor Ping Pong serve)
