(import
 (lofi base)
 (lofi wire)
 (lofi actor)
 (only (lofi primitive) share-value shared-value))

(struct Ping
  ((text String)
   (number I64))
  (deriving Serialize Deserialize))

(struct Pong
  ((text String)
   (number I64))
  (deriving Serialize Deserialize))

(effect test
  ((role (-> I32))
   (target (-> I32))
   (trace (-> Any Unit))
   (observe (-> I64 Unit))
   (wait (-> Unit)))
  (host "snail.test"
        ((role "role")
         (target "target")
         (trace "trace")
         (observe "observe")
         (wait "wait"))))

(: server (-> (Mailbox Ping Pong) Unit ! actors test))
(define (server mailbox)
  (let ((message (receive mailbox)))
    (trace (type-convert message Any))
    (when (or (= (role) 2) (= (role) 8) (= (role) 11)) (wait))
    (when (= (role) 3) (panic "server failed"))
    (unless (= (role) 11)
      (let ((response (Pong (Ping-text message) (+ (Ping-number message) 1))))
        (trace (type-convert response Any))
        (reply mailbox response)))))

(: client (-> Unit ! actors test))
(define (client)
  (let ((server (ann (spawn "server") (Actor Ping Pong))) (message (Ping "hello λ" 41)))
    (trace (type-convert message Any))
    (let ((response (request server message)))
      (trace (type-convert response Any))
      (unless (string=? (Pong-text response) "hello λ") (panic "wrong text"))
      (observe (Pong-number response)))))

;; This fixture alone uses the raw ABI to give two callers an existing
;; endpoint from the test host. The public typed API is exercised above.
(extern ask "snail.actor" "request" (-> I32 Any Any))

(: queued-client (-> Unit ! test))
(define (queued-client)
  (let ((response (ann (shared-value (ask (target) (share-value (Ping "queued" 41)))) Pong)))
    (observe (Pong-number response))))

(: run (-> (Mailbox Ping Pong) Unit ! actors test))
(define (run mailbox)
  (case (role)
    ((0) (client))
    ((4) (ann (spawn "child") (Actor Ping Pong)) (observe 4))
    ((5) (wait) (observe 5))
    ((6) (ann (spawn "server") (Actor Pong Ping)) (unit))
    ((8) (server mailbox) (server mailbox))
    ((9) (observe 9))
    ((10) (queued-client))
    (else (server mailbox))))

(define-actor Ping Pong (test) run)
