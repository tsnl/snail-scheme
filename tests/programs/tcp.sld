(import
 (snail core base)
 (snail core io)
 (snail shell task)
 (snail shell socket))

(: require (All (T) (-> (Result T SocketError) T)))
(define (require result)
  (match result
    ((Ok value) value)
    ((Err error) (panic (SocketError-code error)))))

(: receive-four (-> Connection Bytes ! tcp tasks))
(define (receive-four connection)
  (let loop ((bytes #u8()))
    (if (= (vector-length bytes) 4)
        bytes
        (match (require (read connection (i64->i32 (- 4 (vector-length bytes)))))
          ((Some chunk) (loop (vector-append bytes chunk)))
          ((None) (panic "unexpected EOF"))))))

;; A program waits on sockets from a task, which the scheduler runs once
;; main returns.
(dispatch-local
 (once (lambda ()
         (let* ((listener (require (listen (require (endpoint "127.0.0.1" 0)))))
                (client
                 (require (connect (require (endpoint "127.0.0.1" (Listener-port listener))))))
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

         ;; Only `endpoint` makes an Endpoint: four decimal octets without
         ;; leading zeros, and a port from 0 to 65535.
         (for-each (lambda (address)
                     (match (endpoint address 80)
                       ((Err error) (write-line (SocketError-code error)))
                       ((Ok _) (panic (string-append "accepted " address)))))
                   (list "localhost"
                         "1.2.3"
                         "1.2.3.4.5"
                         "256.1.1.1"
                         "01.2.3.4"
                         "1..3.4"
                         ""
                         "1.2.3.4 "))
         (for-each (lambda (port)
                     (match (endpoint "127.0.0.1" port)
                       ((Err error) (write-line (SocketError-code error)))
                       ((Ok _) (panic "a port out of range was accepted"))))
                   (list -1 65536))
         (write-line (Endpoint-address (require (endpoint "0.0.0.0" 65535))))
         (write-line (Endpoint-address (require (endpoint "255.255.255.255" 0))))

         ;; A token from a replacement handler cannot masquerade as a native handle.
         (match (close-connection (Connection (type-convert (ann 1 I32) Any)))
           ((Err error) (write-line (SocketError-code error)))
           ((Ok _) (panic "a fake token was accepted")))

         ;; Returning from main must close even a delivered listener left open by user code.
         (require (listen (require (endpoint "127.0.0.1" 0))))

         (let* ((listener (require (listen (require (endpoint "127.0.0.1" 0)))))
                (client
                 (require (connect (require (endpoint "127.0.0.1" (Listener-port listener))))))
                (server (require (accept listener))))
           (require (close-listener listener))
           (dispatch-local (once (lambda () (require (finish-connection server 1000)))))
           (require (finish-connection client 1000))
           (write-line "finished")))))
