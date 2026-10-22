(import
 (lofi base)
 (lofi io)
 (lofi actor)
 (ping))

(: run (-> (Mailbox Unit Unit) Unit ! actors console))
(define (run mailbox)
  (let* ((server (ann (spawn "server") (Actor Ping Pong)))
         (pong (request server (Ping "hello from an actor"))))
    (write-line (Pong-text pong))))

(define-actor Unit Unit (console) run)
