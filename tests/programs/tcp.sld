(import
 (snail-core base)
 (snail-core io)
 (snail-core task)
 (snail-core socket))

(: require (All (T) (-> (Result T SocketError) T)))
(define (require result)
  (match result
    ((Ok value) value)
    ((Err error) (panic (SocketError-code error)))))

(: receive-four (-> Connection Bytes ! tcp))
(define (receive-four connection)
  (let loop ((bytes #u8()))
    (if (= (vector-length bytes) 4)
        bytes
        (match (require (read connection (i64->i32 (- 4 (vector-length bytes)))))
          ((Some chunk) (loop (vector-append bytes chunk)))
          ((None) (panic "unexpected EOF"))))))

(let* ((listener (require (listen (Endpoint "127.0.0.1" 0))))
       (client (require (connect (Endpoint "127.0.0.1" (Listener-port listener)))))
       (server (require (accept listener))))
  (require (close-listener listener))
  (require (close-listener listener))
  (display (require (write client #u8(0 255 128 1))))
  (newline)
  (display (vector->list (receive-four server)))
  (newline)
  (require (close-connection client))
  (require (close-connection server))
  (require (close-connection server))
  (match (read server 1)
    ((Err error) (write-line (SocketError-code error)))
    ((Ok _) (panic "closed socket was read"))))

(match (listen (Endpoint "localhost" 0))
  ((Err error) (write-line (SocketError-code error)))
  ((Ok _) (panic "a hostname was accepted")))

;; A token from a replacement handler cannot masquerade as a native handle.
(match (close-connection (Connection (type-convert (ann 1 I32) Any)))
  ((Err error) (write-line (SocketError-code error)))
  ((Ok _) (panic "a fake token was accepted")))

;; Returning from main must close even a delivered listener left open by user code.
(require (listen (Endpoint "127.0.0.1" 0)))

(let* ((listener (require (listen (Endpoint "127.0.0.1" 0))))
       (client (require (connect (Endpoint "127.0.0.1" (Listener-port listener)))))
       (server (require (accept listener))))
  (require (close-listener listener))
  (dispatch-local (once (lambda () (require (finish-connection server 1000)))))
  (require (finish-connection client 1000))
  (write-line "finished"))
